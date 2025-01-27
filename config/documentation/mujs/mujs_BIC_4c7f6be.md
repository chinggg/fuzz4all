Issue #139: Parse integers with floats to support large numbers.

Add a js_strtol which parses integers with bases 2..36 using simple
double precision arithmetic with no overflow checks.


diff --git a/jsbuiltin.c b/jsbuiltin.c
index bf82b60..76a5f68 100644
--- a/jsbuiltin.c
+++ b/jsbuiltin.c
@@ -34,7 +34,7 @@ void jsB_props(js_State *J, const char *name, const char *string)
 static void jsB_parseInt(js_State *J)
 {
 	const char *s = js_tostring(J, 1);
-	int radix = js_isdefined(J, 2) ? js_tointeger(J, 2) : 10;
+	int radix = js_isdefined(J, 2) ? js_tointeger(J, 2) : 0;
 	double sign = 1;
 	double n;
 	char *e;
@@ -57,7 +57,7 @@ static void jsB_parseInt(js_State *J)
 		js_pushnumber(J, NAN);
 		return;
 	}
-	n = strtol(s, &e, radix);
+	n = js_strtol(s, &e, radix);
 	if (s == e)
 		js_pushnumber(J, NAN);
 	else
diff --git a/jsi.h b/jsi.h
index eb2e9fc..6e35926 100644
--- a/jsi.h
+++ b/jsi.h
@@ -114,6 +114,8 @@ void js_fmtexp(char *p, int e);
 int js_grisu2(double v, char *buffer, int *K);
 double js_strtod(const char *as, char **aas);
 
+double js_strtol(const char *s, char **ep, int radix);
+
 /* Private stack functions */
 
 void js_newarguments(js_State *J);
diff --git a/jsvalue.c b/jsvalue.c
index 1f0dd85..c20a621 100644
--- a/jsvalue.c
+++ b/jsvalue.c
@@ -7,6 +7,40 @@
 #define JSV_ISSTRING(v) (v->type==JS_TSHRSTR || v->type==JS_TMEMSTR || v->type==JS_TLITSTR)
 #define JSV_TOSTRING(v) (v->type==JS_TSHRSTR ? v->u.shrstr : v->type==JS_TLITSTR ? v->u.litstr : v->type==JS_TMEMSTR ? v->u.memstr->p : "")
 
+double js_strtol(const char *s, char **p, int base)
+{
+	/* ascii -> digit value. max base is 36. */
+	static const unsigned char table[256] = {
+		80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80,
+		80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80,
+		80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80,
+		0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 80, 80, 80, 80, 80, 80,
+		80, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
+		25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 80, 80, 80, 80, 80,
+		80, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
+		25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 80, 80, 80, 80, 80,
+		80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80,
+		80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80,
+		80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80,
+		80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80,
+		80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80,
+		80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80,
+		80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80,
+		80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80
+	};
+	double x;
+	int c;
+	if (base == 10)
+		for (x = 0, c = *s++; c - '0' < 10; c = *s++)
+			x = x * 10 + (c - '0');
+	else
+		for (x = 0, c = *s++; table[c] < base; c = *s++)
+			x = x * base + table[c];
+	if (p)
+		*p = (char*)s-1;
+	return x;
+}
+
 int jsV_numbertointeger(double n)
 {
 	if (n == 0) return 0;
@@ -172,10 +206,10 @@ double js_stringtofloat(const char *s, char **ep)
 		while (*e >= '0' && *e <= '9') ++e;
 		isflt = 1;
 	}
-	if (isflt || e - s > 9)
+	if (isflt)
 		n = js_strtod(s, &end);
 	else
-		n = strtol(s, &end, 10);
+		n = js_strtol(s, &end, 10);
 	if (end == e) {
 		*ep = (char*)e;
 		return n;
@@ -191,7 +225,7 @@ double jsV_stringtonumber(js_State *J, const char *s)
 	double n;
 	while (jsY_iswhite(*s) || jsY_isnewline(*s)) ++s;
 	if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X') && s[2] != 0)
-		n = strtol(s + 2, &e, 16);
+		n = js_strtol(s + 2, &e, 16);
 	else if (!strncmp(s, "Infinity", 8))
 		n = INFINITY, e = (char*)s + 8;
 	else if (!strncmp(s, "+Infinity", 9))
