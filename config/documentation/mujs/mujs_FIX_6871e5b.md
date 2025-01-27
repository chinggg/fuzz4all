Issue #141: Add missing end-of-string checks in regexp lexer.


diff --git a/regexp.c b/regexp.c
index 12e07ae..66c518d 100644
--- a/regexp.c
+++ b/regexp.c
@@ -132,9 +132,13 @@ static int nextrune(struct cstate *g)
 		case 't': g->yychar = '\t'; return 0;
 		case 'v': g->yychar = '\v'; return 0;
 		case 'c':
+			if (!g->source[0])
+				die(g, "unterminated escape sequence");
 			g->yychar = (*g->source++) & 31;
 			return 0;
 		case 'x':
+			if (!g->source[0] || !g->source[1])
+				die(g, "unterminated escape sequence");
 			g->yychar = hex(g, *g->source++) << 4;
 			g->yychar += hex(g, *g->source++);
 			if (g->yychar == 0) {
@@ -143,6 +147,8 @@ static int nextrune(struct cstate *g)
 			}
 			return 0;
 		case 'u':
+			if (!g->source[0] || !g->source[1] || !g->source[2] || !g->source[3])
+				die(g, "unterminated escape sequence");
 			g->yychar = hex(g, *g->source++) << 12;
 			g->yychar += hex(g, *g->source++) << 8;
 			g->yychar += hex(g, *g->source++) << 4;
