Fix js_strtol

diff --git a/jsvalue.c b/jsvalue.c
index c20a621..4c58d9f 100644
--- a/jsvalue.c
+++ b/jsvalue.c
@@ -31,7 +31,7 @@ double js_strtol(const char *s, char **p, int base)
 	double x;
 	int c;
 	if (base == 10)
-		for (x = 0, c = *s++; c - '0' < 10; c = *s++)
+		for (x = 0, c = *s++; (0 <= c - '0') && (c - '0' < 10); c = *s++)
 			x = x * 10 + (c - '0');
 	else
 		for (x = 0, c = *s++; table[c] < base; c = *s++)
