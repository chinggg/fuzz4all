Fix leak in Function.prototype.toString.


diff --git a/jsfunction.c b/jsfunction.c
index db5a551..2d3cb9e 100644
--- a/jsfunction.c
+++ b/jsfunction.c
@@ -49,34 +49,45 @@ static void jsB_Function_prototype(js_State *J)
 static void Fp_toString(js_State *J)
 {
 	js_Object *self = js_toobject(J, 0);
-	char *s;
-	int i, n;
+	js_Buffer *sb = NULL;
+	int i;
 
 	if (!js_iscallable(J, 0))
 		js_typeerror(J, "not a function");
 
 	if (self->type == JS_CFUNCTION || self->type == JS_CSCRIPT) {
 		js_Function *F = self->u.f.function;
-		n = strlen("function () { ... }");
-		n += strlen(F->name);
-		for (i = 0; i < F->numparams; ++i)
-			n += strlen(F->vartab[i]) + 1;
-		s = js_malloc(J, n + 1);
-		strcpy(s, "function ");
-		strcat(s, F->name);
-		strcat(s, "(");
+
+		if (js_try(J)) {
+			js_free(J, sb);
+			js_throw(J);
+		}
+
+		js_puts(J, &sb, "function ");
+		js_puts(J, &sb, F->name);
+		js_putc(J, &sb, '(');
 		for (i = 0; i < F->numparams; ++i) {
-			if (i > 0) strcat(s, ",");
-			strcat(s, F->vartab[i]);
+			if (i > 0) js_putc(J, &sb, ',');
+			js_puts(J, &sb, F->vartab[i]);
 		}
-		strcat(s, ") { ... }");
+		js_puts(J, &sb, ") { ... }");
+
+		js_pushstring(J, sb->s);
+		js_endtry(J);
+		js_free(J, sb);
+	} else if (self->type == JS_CCFUNCTION) {
 		if (js_try(J)) {
-			js_free(J, s);
+			js_free(J, sb);
 			js_throw(J);
 		}
-		js_pushstring(J, s);
-		js_free(J, s);
+
+		js_puts(J, &sb, "function ");
+		js_puts(J, &sb, self->u.c.name);
+		js_puts(J, &sb, "() { ... }");
+
+		js_pushstring(J, sb->s);
 		js_endtry(J);
+		js_free(J, sb);
 	} else {
 		js_pushliteral(J, "function () { ... }");
 	}
