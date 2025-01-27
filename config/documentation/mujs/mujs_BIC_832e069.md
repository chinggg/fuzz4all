Support 4-byte UTF-8 sequences.

The following functions are no longer restricted to 16-bit integer values:

	String.fromCharCode()
	String.prototype.charCodeAt()

repr() will not escape SMP characters, as doing so would require conversion to
surrogate pairs, but will encode these characters as UTF-8. Unicode characters
in the BMP will still be escaped with \uXXXX as before.

JSON.stringify() only escapes control characters, so will represent all non-ASCII
characters as UTF-8.

We do no automatic conversions to/from surrogate pairs. Code that worked with
surrogate pairs should not be affected by these changes.


diff --git a/json.c b/json.c
index 358d809..e102273 100644
--- a/json.c
+++ b/json.c
@@ -180,10 +180,11 @@ static void fmtnum(js_State *J, js_Buffer **sb, double n)
 static void fmtstr(js_State *J, js_Buffer **sb, const char *s)
 {
 	static const char *HEX = "0123456789ABCDEF";
+	int i, n;
 	Rune c;
 	js_putc(J, sb, '"');
 	while (*s) {
-		s += chartorune(&c, s);
+		n = chartorune(&c, s);
 		switch (c) {
 		case '"': js_puts(J, sb, "\\\""); break;
 		case '\\': js_puts(J, sb, "\\\\"); break;
@@ -193,16 +194,22 @@ static void fmtstr(js_State *J, js_Buffer **sb, const char *s)
 		case '\r': js_puts(J, sb, "\\r"); break;
 		case '\t': js_puts(J, sb, "\\t"); break;
 		default:
-			if (c < ' ' || c > 127) {
-				js_puts(J, sb, "\\u");
+			if (c < ' ') {
+				js_putc(J, sb, '\\');
+				js_putc(J, sb, 'u');
 				js_putc(J, sb, HEX[(c>>12)&15]);
 				js_putc(J, sb, HEX[(c>>8)&15]);
 				js_putc(J, sb, HEX[(c>>4)&15]);
 				js_putc(J, sb, HEX[c&15]);
+			} else if (c < 128) {
+				js_putc(J, sb, c);
 			} else {
-				js_putc(J, sb, c); break;
+				for (i = 0; i < n; ++i)
+					js_putc(J, sb, s[i]);
 			}
+			break;
 		}
+		s += n;
 	}
 	js_putc(J, sb, '"');
 }
diff --git a/jsrepr.c b/jsrepr.c
index e21f9d8..9074f2a 100644
--- a/jsrepr.c
+++ b/jsrepr.c
@@ -19,10 +19,11 @@ static void reprnum(js_State *J, js_Buffer **sb, double n)
 static void reprstr(js_State *J, js_Buffer **sb, const char *s)
 {
 	static const char *HEX = "0123456789ABCDEF";
+	int i, n;
 	Rune c;
 	js_putc(J, sb, '"');
 	while (*s) {
-		s += chartorune(&c, s);
+		n = chartorune(&c, s);
 		switch (c) {
 		case '"': js_puts(J, sb, "\\\""); break;
 		case '\\': js_puts(J, sb, "\\\\"); break;
@@ -32,16 +33,27 @@ static void reprstr(js_State *J, js_Buffer **sb, const char *s)
 		case '\r': js_puts(J, sb, "\\r"); break;
 		case '\t': js_puts(J, sb, "\\t"); break;
 		default:
-			if (c < ' ' || c > 127) {
-				js_puts(J, sb, "\\u");
+			if (c < ' ') {
+				js_putc(J, sb, '\\');
+				js_putc(J, sb, 'x');
+				js_putc(J, sb, HEX[(c>>4)&15]);
+				js_putc(J, sb, HEX[c&15]);
+			} else if (c < 128) {
+				js_putc(J, sb, c);
+			} else if (c < 0x10000) {
+				js_putc(J, sb, '\\');
+				js_putc(J, sb, 'u');
 				js_putc(J, sb, HEX[(c>>12)&15]);
 				js_putc(J, sb, HEX[(c>>8)&15]);
 				js_putc(J, sb, HEX[(c>>4)&15]);
 				js_putc(J, sb, HEX[c&15]);
 			} else {
-				js_putc(J, sb, c); break;
+				for (i = 0; i < n; ++i)
+					js_putc(J, sb, s[i]);
 			}
+			break;
 		}
+		s += n;
 	}
 	js_putc(J, sb, '"');
 }
diff --git a/jsstring.c b/jsstring.c
index b43636b..0bb2f22 100644
--- a/jsstring.c
+++ b/jsstring.c
@@ -310,7 +310,7 @@ static void S_fromCharCode(js_State *J)
 	}
 
 	for (i = 1; i < top; ++i) {
-		c = js_touint16(J, i);
+		c = js_touint32(J, i);
 		p += runetochar(p, &c);
 	}
 	*p = 0;
diff --git a/utf.c b/utf.c
index b3cd420..d42301a 100644
--- a/utf.c
+++ b/utf.c
@@ -25,27 +25,30 @@ enum
 	Bit2	= 5,
 	Bit3	= 4,
 	Bit4	= 3,
+	Bit5	= 2,
 
 	T1	= ((1<<(Bit1+1))-1) ^ 0xFF,	/* 0000 0000 */
 	Tx	= ((1<<(Bitx+1))-1) ^ 0xFF,	/* 1000 0000 */
 	T2	= ((1<<(Bit2+1))-1) ^ 0xFF,	/* 1100 0000 */
 	T3	= ((1<<(Bit3+1))-1) ^ 0xFF,	/* 1110 0000 */
 	T4	= ((1<<(Bit4+1))-1) ^ 0xFF,	/* 1111 0000 */
+	T5	= ((1<<(Bit5+1))-1) ^ 0xFF,	/* 1111 1000 */
 
-	Rune1	= (1<<(Bit1+0*Bitx))-1,		/* 0000 0000 0111 1111 */
-	Rune2	= (1<<(Bit2+1*Bitx))-1,		/* 0000 0111 1111 1111 */
-	Rune3	= (1<<(Bit3+2*Bitx))-1,		/* 1111 1111 1111 1111 */
+	Rune1	= (1<<(Bit1+0*Bitx))-1,		/* 0000 0000 0000 0000 0111 1111 */
+	Rune2	= (1<<(Bit2+1*Bitx))-1,		/* 0000 0000 0000 0111 1111 1111 */
+	Rune3	= (1<<(Bit3+2*Bitx))-1,		/* 0000 0000 1111 1111 1111 1111 */
+	Rune4	= (1<<(Bit4+3*Bitx))-1,		/* 0011 1111 1111 1111 1111 1111 */
 
 	Maskx	= (1<<Bitx)-1,			/* 0011 1111 */
 	Testx	= Maskx ^ 0xFF,			/* 1100 0000 */
 
-	Bad	= Runeerror,
+	Bad	= Runeerror
 };
 
 int
 chartorune(Rune *rune, const char *str)
 {
-	int c, c1, c2;
+	int c, c1, c2, c3;
 	int l;
 
 	/* overlong null character */
@@ -96,6 +99,25 @@ chartorune(Rune *rune, const char *str)
 		return 3;
 	}
 
+	/*
+	 * four character sequence
+	 *	10000-10FFFF => T4 Tx Tx Tx
+	 */
+	if(UTFmax >= 4) {
+		c3 = *(uchar*)(str+3) ^ Tx;
+		if(c3 & Testx)
+			goto bad;
+		if(c < T5) {
+			l = ((((((c << Bitx) | c1) << Bitx) | c2) << Bitx) | c3) & Rune4;
+			if(l <= Rune3)
+				goto bad;
+			if(l > Runemax)
+				goto bad;
+			*rune = l;
+			return 4;
+		}
+	}
+
 	/*
 	 * bad decoding
 	 */
@@ -127,7 +149,7 @@ runetochar(char *str, const Rune *rune)
 
 	/*
 	 * two character sequence
-	 *	0080-07FF => T2 Tx
+	 *	00080-007FF => T2 Tx
 	 */
 	if(c <= Rune2) {
 		str[0] = T2 | (c >> 1*Bitx);
@@ -137,12 +159,26 @@ runetochar(char *str, const Rune *rune)
 
 	/*
 	 * three character sequence
-	 *	0800-FFFF => T3 Tx Tx
+	 *	00800-0FFFF => T3 Tx Tx
+	 */
+	if(c > Runemax)
+		c = Runeerror;
+	if(c <= Rune3) {
+		str[0] = T3 |  (c >> 2*Bitx);
+		str[1] = Tx | ((c >> 1*Bitx) & Maskx);
+		str[2] = Tx |  (c & Maskx);
+		return 3;
+	}
+
+	/*
+	 * four character sequence
+	 *	010000-1FFFFF => T4 Tx Tx Tx
 	 */
-	str[0] = T3 |  (c >> 2*Bitx);
-	str[1] = Tx | ((c >> 1*Bitx) & Maskx);
-	str[2] = Tx |  (c & Maskx);
-	return 3;
+	str[0] = T4 |  (c >> 3*Bitx);
+	str[1] = Tx | ((c >> 2*Bitx) & Maskx);
+	str[2] = Tx | ((c >> 1*Bitx) & Maskx);
+	str[3] = Tx |  (c & Maskx);
+	return 4;
 }
 
 int
diff --git a/utf.h b/utf.h
index 36b299d..04e6bb9 100644
--- a/utf.h
+++ b/utf.h
@@ -1,7 +1,7 @@
 #ifndef js_utf_h
 #define js_utf_h
 
-typedef unsigned short Rune;	/* 16 bits */
+typedef int Rune;	/* 32 bits */
 
 #define chartorune	jsU_chartorune
 #define runetochar	jsU_runetochar
@@ -19,10 +19,11 @@ typedef unsigned short Rune;	/* 16 bits */
 
 enum
 {
-	UTFmax		= 3,		/* maximum bytes per rune */
+	UTFmax		= 4,		/* maximum bytes per rune */
 	Runesync	= 0x80,		/* cannot represent part of a UTF sequence (<) */
 	Runeself	= 0x80,		/* rune and UTF sequences are the same (<) */
 	Runeerror	= 0xFFFD,	/* decoding error in UTF */
+	Runemax		= 0x10FFFF,	/* maximum rune value */
 };
 
 int	chartorune(Rune *rune, const char *str);
