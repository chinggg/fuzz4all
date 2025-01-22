Why Choose MuJS?
Javascript is a proven scripting language
Javascript is one of the most popular programming languages in the world. It is a powerful extension language, used everywhere on the web — both as a way to add interactivity to web pages in the browser, and on the server side with platforms like node.js.

With MuJS you can bring this power to your application as well!

MuJS is standards compliant
MuJS implements ES5. There are no non-standard extensions, so you can remain confident that Javascript code that runs on MuJS will also run on any other standards compliant Javascript implementation.

MuJS is portable
MuJS is written in portable C and can be built by compiling a single C file using any standard C compiler. There is no need for configuration or fancy build systems. MuJS runs on all flavors of Unix and Windows, on mobile devices (such as Android and iOS), embedded microprocessors (such as the Beagle board and Raspberry Pi), etc.

MuJS is embeddable
MuJS is a simple language engine with a small footprint that you can easily embed into your application. The API is simple and well documented and allows strong integration with code written in other languages. You don't need to work with byzantine C++ templating mechanisms, or manually manage garbage collection roots. It is easy to extend MuJS with libraries written in other languages. It is also easy to extend programs written in other languages with MuJS.

MuJS is small
Adding MuJS to an application does not bloat it. The source contains around 15'000 lines of C. Under 64-bit Linux, the compiled library takes 180kB if optimized for size, and 260kB if optimized for speed. Compare this with V8, SpiderMonkey or JavaScriptCore, which are all several hundred thousand lines of code take several megabytes of space, and require the C++ runtime.

MuJS is reasonably fast and secure
It is a bytecode interpreter with a very fast mechanism to call-out to C. The default build is sandboxed with very restricted access to resources. Due to the nature of bytecode, MuJS is not as fast as JIT compiling implementations but starts up faster and uses fewer resources. If you implement heavy lifting in C code, controlled by Javascript, you can get the best of both worlds.

MuJS is free software
MuJS is free open source software distributed under the ISC license.

MuJS is developed by a stable company
Artifex Software has long experience in interpreters and page description languages, and has a history with open source that goes back to 1993 when it was created to facilitate licensing Ghostscript to OEMs.