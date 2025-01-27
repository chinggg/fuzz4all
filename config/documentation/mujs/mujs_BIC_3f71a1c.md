Fast path for "simple" arrays.

An array without holes and with only integer properties can be represented
with a "flat" array part that allows for O(1) property access.

If we ever add a non-integer property, create holes in the array,
the whole array is unpacked into a normal string-keyed object.

Also add fast integer indexing to be used on these arrays, before falling
back to converting the integer to a string property lookup.

Use JS_ARRAYLIMIT to restrict size of arrays to avoid integer overflows and out
of memory thrashing.


diff --git a/jsarray.c b/jsarray.c
index 9049af6..3954951 100644
--- a/jsarray.c
+++ b/jsarray.c
@@ -17,30 +17,6 @@ void js_setlength(js_State *J, int idx, int len)
 	js_setproperty(J, idx < 0 ? idx - 1 : idx, "length");
 }
 
-int js_hasindex(js_State *J, int idx, int i)
-{
-	char buf[32];
-	return js_hasproperty(J, idx, js_itoa(buf, i));
-}
-
-void js_getindex(js_State *J, int idx, int i)
-{
-	char buf[32];
-	js_getproperty(J, idx, js_itoa(buf, i));
-}
-
-void js_setindex(js_State *J, int idx, int i)
-{
-	char buf[32];
-	js_setproperty(J, idx, js_itoa(buf, i));
-}
-
-void js_delindex(js_State *J, int idx, int i)
-{
-	char buf[32];
-	js_delproperty(J, idx, js_itoa(buf, i));
-}
-
 static void jsB_new_Array(js_State *J)
 {
 	int i, top = js_gettop(J);
diff --git a/jsgc.c b/jsgc.c
index b6dd406..4125644 100644
--- a/jsgc.c
+++ b/jsgc.c
@@ -42,6 +42,8 @@ static void jsG_freeobject(js_State *J, js_Object *obj)
 		js_free(J, obj->u.r.source);
 		js_regfreex(J->alloc, J->actx, obj->u.r.prog);
 	}
+	if (obj->type == JS_CARRAY && obj->u.a.simple)
+		js_free(J, obj->u.a.array);
 	if (obj->type == JS_CITERATOR)
 		jsG_freeiterator(J, obj->u.iter.head);
 	if (obj->type == JS_CUSERDATA && obj->u.user.finalize)
@@ -100,6 +102,16 @@ static void jsG_scanobject(js_State *J, int mark, js_Object *obj)
 		jsG_markproperty(J, mark, obj->properties);
 	if (obj->prototype && obj->prototype->gcmark != mark)
 		jsG_markobject(J, mark, obj->prototype);
+	if (obj->type == JS_CARRAY && obj->u.a.simple) {
+		int i;
+		for (i = 0; i < obj->u.a.length; ++i) {
+			js_Value *v = &obj->u.a.array[i];
+			if (v->type == JS_TMEMSTR && v->u.memstr->gcmark != mark)
+				v->u.memstr->gcmark = mark;
+			if (v->type == JS_TOBJECT && v->u.object->gcmark != mark)
+				jsG_markobject(J, mark, v->u.object);
+		}
+	}
 	if (obj->type == JS_CITERATOR && obj->u.iter.target->gcmark != mark) {
 		jsG_markobject(J, mark, obj->u.iter.target);
 	}
diff --git a/jsi.h b/jsi.h
index c9e17fd..3aeda11 100644
--- a/jsi.h
+++ b/jsi.h
@@ -86,6 +86,9 @@ typedef struct js_StackTrace js_StackTrace;
 #ifndef JS_TRYLIMIT
 #define JS_TRYLIMIT 64		/* exception stack size */
 #endif
+#ifndef JS_ARRAYLIMIT
+#define JS_ARRAYLIMIT (1<<26)	/* limit arrays to 64M entries (1G of flat array data) */
+#endif
 #ifndef JS_GCFACTOR
 /*
  * GC will try to trigger when memory usage is this value times the minimum
diff --git a/jsobject.c b/jsobject.c
index 23fb901..78ea344 100644
--- a/jsobject.c
+++ b/jsobject.c
@@ -62,7 +62,24 @@ static void Op_hasOwnProperty(js_State *J)
 {
 	js_Object *self = js_toobject(J, 0);
 	const char *name = js_tostring(J, 1);
-	js_Property *ref = jsV_getownproperty(J, self, name);
+	js_Property *ref;
+	int k;
+
+	if (self->type == JS_CSTRING) {
+		if (js_isarrayindex(J, name, &k) && k >= 0 && k < self->u.s.length) {
+			js_pushboolean(J, 1);
+			return;
+		}
+	}
+
+	if (self->type == JS_CARRAY && self->u.a.simple) {
+		if (js_isarrayindex(J, name, &k) && k >= 0 && k < self->u.a.length) {
+			js_pushboolean(J, 1);
+			return;
+		}
+	}
+
+	ref = jsV_getownproperty(J, self, name);
 	js_pushboolean(J, ref != NULL);
 }
 
@@ -110,9 +127,10 @@ static void O_getOwnPropertyDescriptor(js_State *J)
 		js_typeerror(J, "not an object");
 	obj = js_toobject(J, 1);
 	ref = jsV_getproperty(J, obj, js_tostring(J, 2));
-	if (!ref)
+	if (!ref) {
+		// TODO: builtin properties (string and array index and length, regexp flags, etc)
 		js_pushundefined(J);
-	else {
+	} else {
 		js_newobject(J);
 		if (!ref->getter && !ref->setter) {
 			js_pushvalue(J, ref->value);
@@ -152,6 +170,7 @@ static int O_getOwnPropertyNames_walk(js_State *J, js_Property *ref, int i)
 static void O_getOwnPropertyNames(js_State *J)
 {
 	js_Object *obj;
+	char name[32];
 	int k;
 	int i;
 
@@ -169,13 +188,21 @@ static void O_getOwnPropertyNames(js_State *J)
 	if (obj->type == JS_CARRAY) {
 		js_pushliteral(J, "length");
 		js_setindex(J, -2, i++);
+		if (obj->u.a.simple) {
+			for (k = 0; k < obj->u.a.length; ++k) {
+				js_itoa(name, k);
+				js_pushstring(J, name);
+				js_setindex(J, -2, i++);
+			}
+		}
 	}
 
 	if (obj->type == JS_CSTRING) {
 		js_pushliteral(J, "length");
 		js_setindex(J, -2, i++);
 		for (k = 0; k < obj->u.s.length; ++k) {
-			js_pushnumber(J, k);
+			js_itoa(name, k);
+			js_pushstring(J, name);
 			js_setindex(J, -2, i++);
 		}
 	}
@@ -359,9 +386,12 @@ static void O_keys(js_State *J)
 
 static void O_preventExtensions(js_State *J)
 {
+	js_Object *obj;
 	if (!js_isobject(J, 1))
 		js_typeerror(J, "not an object");
-	js_toobject(J, 1)->extensible = 0;
+	obj = js_toobject(J, 1);
+	jsR_unflattenarray(J, obj);
+	obj->extensible = 0;
 	js_copy(J, 1);
 }
 
@@ -389,6 +419,7 @@ static void O_seal(js_State *J)
 		js_typeerror(J, "not an object");
 
 	obj = js_toobject(J, 1);
+	jsR_unflattenarray(J, obj);
 	obj->extensible = 0;
 
 	if (obj->properties->level)
@@ -446,6 +477,7 @@ static void O_freeze(js_State *J)
 		js_typeerror(J, "not an object");
 
 	obj = js_toobject(J, 1);
+	jsR_unflattenarray(J, obj);
 	obj->extensible = 0;
 
 	if (obj->properties->level)
diff --git a/jsproperty.c b/jsproperty.c
index 292e8b5..6e6304a 100644
--- a/jsproperty.c
+++ b/jsproperty.c
@@ -1,6 +1,8 @@
 #include "jsi.h"
 #include "jsvalue.h"
 
+#include <assert.h>
+
 /*
 	Use an AA-tree to quickly look up properties in objects:
 
@@ -226,16 +228,28 @@ void jsV_delproperty(js_State *J, js_Object *obj, const char *name)
 
 /* Flatten hierarchy of enumerable properties into an iterator object */
 
+static js_Iterator *itnewnode(js_State *J, const char *name, js_Iterator *next) {
+	js_Iterator *node = js_malloc(J, offsetof(js_Iterator, buf));
+	node->name = name;
+	node->next = next;
+	return node;
+}
+
+static js_Iterator *itnewnodeix(js_State *J, int ix) {
+	js_Iterator *node = js_malloc(J, sizeof(js_Iterator));
+	js_itoa(node->buf, ix);
+	node->name = node->buf;
+	node->next = NULL;
+	return node;
+}
+
 static js_Iterator *itwalk(js_State *J, js_Iterator *iter, js_Property *prop, js_Object *seen)
 {
 	if (prop->right != &sentinel)
 		iter = itwalk(J, iter, prop->right, seen);
 	if (!(prop->atts & JS_DONTENUM)) {
 		if (!seen || !jsV_getenumproperty(J, seen, prop->name)) {
-			js_Iterator *head = js_malloc(J, sizeof *head);
-			head->name = prop->name;
-			head->next = iter;
-			iter = head;
+			iter = itnewnode(J, prop->name, iter);
 		}
 	}
 	if (prop->left != &sentinel)
@@ -266,6 +280,7 @@ js_Object *jsV_newiterator(js_State *J, js_Object *obj, int own)
 	} else {
 		io->u.iter.head = itflatten(J, obj);
 	}
+
 	if (obj->type == JS_CSTRING) {
 		js_Iterator *tail = io->u.iter.head;
 		if (tail)
@@ -274,9 +289,7 @@ js_Object *jsV_newiterator(js_State *J, js_Object *obj, int own)
 		for (k = 0; k < obj->u.s.length; ++k) {
 			js_itoa(buf, k);
 			if (!jsV_getenumproperty(J, obj, buf)) {
-				js_Iterator *node = js_malloc(J, sizeof *node);
-				node->name = js_intern(J, js_itoa(buf, k));
-				node->next = NULL;
+				js_Iterator *node = itnewnodeix(J, k);
 				if (!tail)
 					io->u.iter.head = tail = node;
 				else {
@@ -286,6 +299,23 @@ js_Object *jsV_newiterator(js_State *J, js_Object *obj, int own)
 			}
 		}
 	}
+
+	if (obj->type == JS_CARRAY && obj->u.a.simple) {
+		js_Iterator *tail = io->u.iter.head;
+		if (tail)
+			while (tail->next)
+				tail = tail->next;
+		for (k = 0; k < obj->u.a.length; ++k) {
+			js_Iterator *node = itnewnodeix(J, k);
+			if (!tail)
+				io->u.iter.head = tail = node;
+			else {
+				tail->next = node;
+				tail = node;
+			}
+		}
+	}
+
 	return io;
 }
 
@@ -304,6 +334,9 @@ const char *jsV_nextiterator(js_State *J, js_Object *io)
 		if (io->u.iter.target->type == JS_CSTRING)
 			if (js_isarrayindex(J, name, &k) && k < io->u.iter.target->u.s.length)
 				return name;
+		if (io->u.iter.target->type == JS_CARRAY && io->u.iter.target->u.a.simple)
+			if (js_isarrayindex(J, name, &k) && k < io->u.iter.target->u.a.length)
+				return name;
 	}
 	return NULL;
 }
@@ -315,6 +348,7 @@ void jsV_resizearray(js_State *J, js_Object *obj, int newlen)
 	char buf[32];
 	const char *s;
 	int k;
+	assert(!obj->u.a.simple);
 	if (newlen < obj->u.a.length) {
 		if (obj->u.a.length > obj->count * 2) {
 			js_Object *it = jsV_newiterator(J, obj, 1);
diff --git a/jsrun.c b/jsrun.c
index dd96e7e..cc76d69 100644
--- a/jsrun.c
+++ b/jsrun.c
@@ -5,6 +5,8 @@
 
 #include "utf.h"
 
+#include <assert.h>
+
 static void jsR_run(js_State *J, js_Function *F);
 
 /* Push values on stack */
@@ -517,6 +519,28 @@ static void js_pushrune(js_State *J, Rune rune)
 	}
 }
 
+void jsR_unflattenarray(js_State *J, js_Object *obj) {
+	if (obj->type == JS_CARRAY && obj->u.a.simple) {
+		js_Property *ref;
+		int i;
+		char name[32];
+		if (js_try(J)) {
+			obj->properties = NULL;
+			js_throw(J);
+		}
+		for (i = 0; i < obj->u.a.length; ++i) {
+			js_itoa(name, i);
+			ref = jsV_setproperty(J, obj, name);
+			ref->value = obj->u.a.array[i];
+		}
+		js_free(J, obj->u.a.array);
+		obj->u.a.simple = 0;
+		obj->u.a.capacity = 0;
+		obj->u.a.array = NULL;
+		js_endtry(J);
+	}
+}
+
 static int jsR_hasproperty(js_State *J, js_Object *obj, const char *name)
 {
 	js_Property *ref;
@@ -527,6 +551,14 @@ static int jsR_hasproperty(js_State *J, js_Object *obj, const char *name)
 			js_pushnumber(J, obj->u.a.length);
 			return 1;
 		}
+		if (obj->u.a.simple) {
+			if (js_isarrayindex(J, name, &k)) {
+				if (k >= 0 && k < obj->u.a.length) {
+					js_pushvalue(J, obj->u.a.array[k]);
+					return 1;
+				}
+			}
+		}
 	}
 
 	else if (obj->type == JS_CSTRING) {
@@ -591,6 +623,45 @@ static void jsR_getproperty(js_State *J, js_Object *obj, const char *name)
 		js_pushundefined(J);
 }
 
+static int jsR_hasindex(js_State *J, js_Object *obj, int k)
+{
+	char buf[32];
+	if (obj->type == JS_CARRAY && obj->u.a.simple && k >= 0 && k < obj->u.a.length) {
+		js_pushvalue(J, obj->u.a.array[k]);
+		return 1;
+	}
+	return jsR_hasproperty(J, obj, js_itoa(buf, k));
+}
+
+static void jsR_getindex(js_State *J, js_Object *obj, int k)
+{
+	if (!jsR_hasindex(J, obj, k))
+		js_pushundefined(J);
+}
+
+static void jsR_setarrayindex(js_State *J, js_Object *obj, int k, js_Value *value)
+{
+	int newlen = k + 1;
+	assert(obj->u.a.simple);
+	assert(k >= 0);
+	if (newlen > JS_ARRAYLIMIT)
+		js_rangeerror(J, "array too large");
+	if (newlen > obj->u.a.length) {
+		assert(newlen == obj->u.a.length + 1);
+		if (newlen > obj->u.a.capacity) {
+			int newcap = obj->u.a.capacity;
+			if (newcap == 0)
+				newcap = 8;
+			while (newcap < newlen)
+				newcap <<= 1;
+			obj->u.a.array = js_realloc(J, obj->u.a.array, newcap * sizeof(js_Value));
+			obj->u.a.capacity = newcap;
+		}
+		obj->u.a.length = newlen;
+	}
+	obj->u.a.array[k] = *value;
+}
+
 static void jsR_setproperty(js_State *J, js_Object *obj, const char *name, int transient)
 {
 	js_Value *value = stackidx(J, -1);
@@ -604,12 +675,30 @@ static void jsR_setproperty(js_State *J, js_Object *obj, const char *name, int t
 			int newlen = jsV_numbertointeger(rawlen);
 			if (newlen != rawlen || newlen < 0)
 				js_rangeerror(J, "invalid array length");
+			if (newlen > JS_ARRAYLIMIT)
+				js_rangeerror(J, "array too large");
+			if (obj->u.a.simple) {
+				if (newlen <= obj->u.a.length) {
+					obj->u.a.length = newlen;
+					return;
+				}
+				jsR_unflattenarray(J, obj);
+			}
 			jsV_resizearray(J, obj, newlen);
 			return;
 		}
-		if (js_isarrayindex(J, name, &k))
-			if (k >= obj->u.a.length)
+
+		if (js_isarrayindex(J, name, &k)) {
+			if (obj->u.a.simple) {
+				if (k >= 0 && k <= obj->u.a.length) {
+					jsR_setarrayindex(J, obj, k, value);
+					return;
+				}
+				jsR_unflattenarray(J, obj);
+			}
+			if (k + 1 > obj->u.a.length)
 				obj->u.a.length = k + 1;
+		}
 	}
 
 	else if (obj->type == JS_CSTRING) {
@@ -679,6 +768,16 @@ readonly:
 		js_typeerror(J, "'%s' is read-only", name);
 }
 
+static void jsR_setindex(js_State *J, js_Object *obj, int k, int transient)
+{
+	char buf[32];
+	if (obj->type == JS_CARRAY && obj->u.a.simple && k >= 0 && k <= obj->u.a.length) {
+		jsR_setarrayindex(J, obj, k, stackidx(J, -1));
+	} else {
+		jsR_setproperty(J, obj, js_itoa(buf, k), transient);
+	}
+}
+
 static void jsR_defproperty(js_State *J, js_Object *obj, const char *name,
 	int atts, js_Value *value, js_Object *getter, js_Object *setter,
 	int throw)
@@ -689,6 +788,8 @@ static void jsR_defproperty(js_State *J, js_Object *obj, const char *name,
 	if (obj->type == JS_CARRAY) {
 		if (!strcmp(name, "length"))
 			goto readonly;
+		if (obj->u.a.simple)
+			jsR_unflattenarray(J, obj);
 	}
 
 	else if (obj->type == JS_CSTRING) {
@@ -750,6 +851,8 @@ static int jsR_delproperty(js_State *J, js_Object *obj, const char *name)
 	if (obj->type == JS_CARRAY) {
 		if (!strcmp(name, "length"))
 			goto dontconf;
+		if (obj->u.a.simple)
+			jsR_unflattenarray(J, obj);
 	}
 
 	else if (obj->type == JS_CSTRING) {
@@ -889,6 +992,28 @@ int js_hasproperty(js_State *J, int idx, const char *name)
 	return jsR_hasproperty(J, js_toobject(J, idx), name);
 }
 
+void js_getindex(js_State *J, int idx, int i)
+{
+	jsR_getindex(J, js_toobject(J, idx), i);
+}
+
+int js_hasindex(js_State *J, int idx, int i)
+{
+	return jsR_hasindex(J, js_toobject(J, idx), i);
+}
+
+void js_setindex(js_State *J, int idx, int i)
+{
+	jsR_setindex(J, js_toobject(J, idx), i, !js_isobject(J, idx));
+	js_pop(J, 1);
+}
+
+void js_delindex(js_State *J, int idx, int i)
+{
+	char buf[32];
+	js_delproperty(J, idx, js_itoa(buf, i));
+}
+
 /* Iterator */
 
 void js_pushiterator(js_State *J, int idx, int own)
@@ -1360,6 +1485,16 @@ void js_trap(js_State *J, int pc)
 	js_stacktrace(J);
 }
 
+static int jsR_isindex(js_State *J, int idx, int *k)
+{
+	js_Value *v = stackidx(J, idx);
+	if (v->type == JS_TNUMBER) {
+		*k = v->u.number;
+		return *k == v->u.number && *k >= 0;
+	}
+	return 0;
+}
+
 static void jsR_run(js_State *J, js_Function *F)
 {
 	js_Function **FT = F->funtab;
@@ -1532,9 +1667,14 @@ static void jsR_run(js_State *J, js_Function *F)
 			break;
 
 		case OP_GETPROP:
-			str = js_tostring(J, -1);
-			obj = js_toobject(J, -2);
-			jsR_getproperty(J, obj, str);
+			if (jsR_isindex(J, -1, &ix)) {
+				obj = js_toobject(J, -2);
+				jsR_getindex(J, obj, ix);
+			} else {
+				str = js_tostring(J, -1);
+				obj = js_toobject(J, -2);
+				jsR_getproperty(J, obj, str);
+			}
 			js_rot3pop2(J);
 			break;
 
@@ -1546,10 +1686,16 @@ static void jsR_run(js_State *J, js_Function *F)
 			break;
 
 		case OP_SETPROP:
-			str = js_tostring(J, -2);
-			obj = js_toobject(J, -3);
-			transient = !js_isobject(J, -3);
-			jsR_setproperty(J, obj, str, transient);
+			if (jsR_isindex(J, -2, &ix)) {
+				obj = js_toobject(J, -3);
+				transient = !js_isobject(J, -3);
+				jsR_setindex(J, obj, ix, transient);
+			} else {
+				str = js_tostring(J, -2);
+				obj = js_toobject(J, -3);
+				transient = !js_isobject(J, -3);
+				jsR_setproperty(J, obj, str, transient);
+			}
 			js_rot3pop2(J);
 			break;
 
diff --git a/jsvalue.c b/jsvalue.c
index 77ad237..ba2ca94 100644
--- a/jsvalue.c
+++ b/jsvalue.c
@@ -423,7 +423,9 @@ void js_newarguments(js_State *J)
 
 void js_newarray(js_State *J)
 {
-	js_pushobject(J, jsV_newobject(J, JS_CARRAY, J->Array_prototype));
+	js_Object *obj = jsV_newobject(J, JS_CARRAY, J->Array_prototype);
+	obj->u.a.simple = 1;
+	js_pushobject(J, obj);
 }
 
 void js_newboolean(js_State *J, int v)
diff --git a/jsvalue.h b/jsvalue.h
index 880efe4..3152dc2 100644
--- a/jsvalue.h
+++ b/jsvalue.h
@@ -93,6 +93,9 @@ struct js_Object
 		} s;
 		struct {
 			int length;
+			int simple; // true if array has only non-sparse array properties
+			int capacity;
+			js_Value *array;
 		} a;
 		struct {
 			js_Function *function;
@@ -140,6 +143,7 @@ struct js_Iterator
 {
 	const char *name;
 	js_Iterator *next;
+	char buf[12]; /* for integer iterators */
 };
 
 /* jsrun.c */
@@ -149,6 +153,7 @@ void js_toprimitive(js_State *J, int idx, int hint);
 js_Object *js_toobject(js_State *J, int idx);
 void js_pushvalue(js_State *J, js_Value v);
 void js_pushobject(js_State *J, js_Object *v);
+void jsR_unflattenarray(js_State *J, js_Object *obj);
 
 /* jsvalue.c */
 int jsV_toboolean(js_State *J, js_Value *v);
@@ -158,7 +163,7 @@ const char *jsV_tostring(js_State *J, js_Value *v);
 js_Object *jsV_toobject(js_State *J, js_Value *v);
 void jsV_toprimitive(js_State *J, js_Value *v, int preferred);
 
-const char *js_itoa(char buf[32], int a);
+const char *js_itoa(char *buf, int a);
 double js_stringtofloat(const char *s, char **ep);
 int jsV_numbertointeger(double n);
 int jsV_numbertoint32(double n);
@@ -182,6 +187,9 @@ const char *jsV_nextiterator(js_State *J, js_Object *iter);
 
 void jsV_resizearray(js_State *J, js_Object *obj, int newlen);
 
+void jsV_unflattenarray(js_State *J, js_Object *obj);
+void jsV_growarray(js_State *J, js_Object *obj);
+
 /* jsdump.c */
 void js_dumpobject(js_State *J, js_Object *obj);
 void js_dumpvalue(js_State *J, js_Value v);
