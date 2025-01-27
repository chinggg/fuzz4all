Issue #166: Use special iterator for string and array indices.

Add a scratch buffer to js_State to hold temporary strings.


diff --git a/jsi.h b/jsi.h
index 3aeda11..f9fd32c 100644
--- a/jsi.h
+++ b/jsi.h
@@ -244,6 +244,8 @@ struct js_State
 
 	unsigned int seed; /* Math.random seed */
 
+	char scratch[12]; /* scratch buffer for iterating over array indices */
+
 	int nextref; /* for js_ref use */
 	js_Object *R; /* registry of hidden values */
 	js_Object *G; /* the global object */
diff --git a/jsproperty.c b/jsproperty.c
index 6e6304a..f2e23b7 100644
--- a/jsproperty.c
+++ b/jsproperty.c
@@ -229,20 +229,12 @@ void jsV_delproperty(js_State *J, js_Object *obj, const char *name)
 /* Flatten hierarchy of enumerable properties into an iterator object */
 
 static js_Iterator *itnewnode(js_State *J, const char *name, js_Iterator *next) {
-	js_Iterator *node = js_malloc(J, offsetof(js_Iterator, buf));
+	js_Iterator *node = js_malloc(J, sizeof(js_Iterator));
 	node->name = name;
 	node->next = next;
 	return node;
 }
 
-static js_Iterator *itnewnodeix(js_State *J, int ix) {
-	js_Iterator *node = js_malloc(J, sizeof(js_Iterator));
-	js_itoa(node->buf, ix);
-	node->name = node->buf;
-	node->next = NULL;
-	return node;
-}
-
 static js_Iterator *itwalk(js_State *J, js_Iterator *iter, js_Property *prop, js_Object *seen)
 {
 	if (prop->right != &sentinel)
@@ -269,10 +261,10 @@ static js_Iterator *itflatten(js_State *J, js_Object *obj)
 
 js_Object *jsV_newiterator(js_State *J, js_Object *obj, int own)
 {
-	char buf[32];
-	int k;
 	js_Object *io = jsV_newobject(J, JS_CITERATOR, NULL);
 	io->u.iter.target = obj;
+	io->u.iter.i = 0;
+	io->u.iter.n = 0;
 	if (own) {
 		io->u.iter.head = NULL;
 		if (obj->properties != &sentinel)
@@ -281,40 +273,11 @@ js_Object *jsV_newiterator(js_State *J, js_Object *obj, int own)
 		io->u.iter.head = itflatten(J, obj);
 	}
 
-	if (obj->type == JS_CSTRING) {
-		js_Iterator *tail = io->u.iter.head;
-		if (tail)
-			while (tail->next)
-				tail = tail->next;
-		for (k = 0; k < obj->u.s.length; ++k) {
-			js_itoa(buf, k);
-			if (!jsV_getenumproperty(J, obj, buf)) {
-				js_Iterator *node = itnewnodeix(J, k);
-				if (!tail)
-					io->u.iter.head = tail = node;
-				else {
-					tail->next = node;
-					tail = node;
-				}
-			}
-		}
-	}
+	if (obj->type == JS_CSTRING)
+		io->u.iter.n = obj->u.s.length;
 
-	if (obj->type == JS_CARRAY && obj->u.a.simple) {
-		js_Iterator *tail = io->u.iter.head;
-		if (tail)
-			while (tail->next)
-				tail = tail->next;
-		for (k = 0; k < obj->u.a.length; ++k) {
-			js_Iterator *node = itnewnodeix(J, k);
-			if (!tail)
-				io->u.iter.head = tail = node;
-			else {
-				tail->next = node;
-				tail = node;
-			}
-		}
-	}
+	if (obj->type == JS_CARRAY && obj->u.a.simple)
+		io->u.iter.n = obj->u.a.length;
 
 	return io;
 }
@@ -324,6 +287,11 @@ const char *jsV_nextiterator(js_State *J, js_Object *io)
 	int k;
 	if (io->type != JS_CITERATOR)
 		js_typeerror(J, "not an iterator");
+	if (io->u.iter.i < io->u.iter.n) {
+		js_itoa(J->scratch, io->u.iter.i);
+		io->u.iter.i++;
+		return J->scratch;
+	}
 	while (io->u.iter.head) {
 		js_Iterator *next = io->u.iter.head->next;
 		const char *name = io->u.iter.head->name;
diff --git a/jsvalue.h b/jsvalue.h
index 3152dc2..8e1ca82 100644
--- a/jsvalue.h
+++ b/jsvalue.h
@@ -93,7 +93,7 @@ struct js_Object
 		} s;
 		struct {
 			int length;
-			int simple; // true if array has only non-sparse array properties
+			int simple; /* true if array has only non-sparse array properties */
 			int capacity;
 			js_Value *array;
 		} a;
@@ -112,7 +112,8 @@ struct js_Object
 		js_Regexp r;
 		struct {
 			js_Object *target;
-			js_Iterator *head;
+			int i, n; /* for array part */
+			js_Iterator *head; /* for object part */
 		} iter;
 		struct {
 			const char *tag;
@@ -143,7 +144,6 @@ struct js_Iterator
 {
 	const char *name;
 	js_Iterator *next;
-	char buf[12]; /* for integer iterators */
 };
 
 /* jsrun.c */
