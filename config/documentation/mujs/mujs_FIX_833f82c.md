Fix issue #65: Uninitialized name in Function.prototype function.


diff --git a/jsfunction.c b/jsfunction.c
index e212b0e..bdaaa93 100644
--- a/jsfunction.c
+++ b/jsfunction.c
@@ -212,8 +212,10 @@ static void Fp_bind(js_State *J)
 
 void jsB_initfunction(js_State *J)
 {
+	J->Function_prototype->u.c.name = "Function.prototype";
 	J->Function_prototype->u.c.function = jsB_Function_prototype;
 	J->Function_prototype->u.c.constructor = NULL;
+	J->Function_prototype->u.c.length = 0;
 
 	js_pushobject(J, J->Function_prototype);
 	{
