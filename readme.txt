

This is a preview of a major update that I'm working on (very slowly). While the 
code in previous versions was functional, in many places it is/was downright 
ugly. This new version is a significant rewrite and should be a little easier to 
understand and maintain. There is also a reasonable performance improvement. 
However, at the moment this new version only performs basic clipping as there's 
no merging or simplifying of polygons with common/touching edges in clipping 
solutions. (This was always incomplete in previous versions). The 'offsetting' 
code has also undergone significant revision.

There are quite a few changes to public types and methods in the new library. 
Here are the more notable ones ...
1. The PolyFillType enumeration type name has been simplified to FillType.
2. The cInt type is now Int64 as there's no longer any additional restriction 
   on the size of Int64 path coordinates.
3. Likewise the IntPoint and IntRect types have been renamed Point64 and Rect64
   respectively (or TPoint64 and TInt64 in Delphi).
4. The Clipper object's Execute parameters have changed: an (optional) OpenPaths
   parameter has been added; and there's now only one PolyFillType parameter. 
   (On reflection it seemed unnecessarily complicated and highy unlikely that 
   users would need different FillType types for Subject and Clip paths.)
5. The Polytree class now contains only closed paths (ie polygons) since open 
   paths can't contain/own polygons. (Any open paths are now returned via a 
   separate parameter in the Clipper object's Execute method.)
6. The optional Closed parameter in the AddPath and AddPaths methods has changed 
   to IsOpen (and now defaults to false).

When I originally translated the Library from Delphi (Pascal) to C# and C++,
I deliberately kept a strong Delphi naming style as I thought this would help
with maintainance. In hindsight this was a mistake. It didn't really achieve
that goal and just meant the C# and C++ code looked odd. With this new version, 
I've attempted to adopt a more typical style for each of these three languages, 
while acknowledging that I still have limited experience coding in C# and C++.


Below I've benchmarked a few comparisons between the old (ver 6.4.2) and this 
Clipper. (The old version has also had the polygon 'merging' code removed so 
we're comparing 'apples with apples'. Tests 1a and 2 were compiled (for 32bit) 
using Delphi 10.1 on a Windows 10 64Bit PC with Intel i7 2.0GHz CPU & 8GB RAM.
Test 1b was compiled (for 32bit) using C# code and compiled using Microsoft's 
Visual Studio Community 2017 on the same PC.

TEST1a: Time (secs) to intersect COMPLEX polygons - a single random subject 
and a single clip polygon with varying number of edges (32bit compile).
+===================+=========+=========+=======+
|No. Edges          | New     | Old     | Perf. |
|(each)             | Clipper | Clipper | Incr. |  
+===================+=========+=========+=======+
| 100               |   0.002 |   0.002 |   5%  |
| 500               |   0.068 |   0.98  |  36%  |
|1000               |   0.32  |   0.64  | 100%  |
|2000               |   4.9   |   8.9   |  81%  |
|2500               |  11.9   |  23.9   | 100%  |
|3000               |  27.3   |  52.6   |  93%  |
|3500               |  57.2   | 106.5   |  86%  |
|4000               | 108.1   | 205.5   |  90%  |
|4500               | 194.0   | 343.1   |  77%  |
|5000               | 287.2   | 569.1   |  98%  |
+===================+=========+=========+=======+
Vertex coordinate ranges X:0-800, Y:0-600 (rounded to nearest 10).

TEST1b: Same test as above but using C# code (64bit compile).
+===================+=========+=========+=======+
|No. Edges          | New     | Old     | Perf. |
|(each)             | Clipper | Clipper | Incr. |  
+===================+=========+=========+=======+
| 100               |   0.002 |   0.003 |   50% |   
| 500               |   0.074 |   0.148 |  100% |
|1000               |   0.422 |   0.729 |   73% |
|2000               |   3.87  |    7.34 |   90% |
|2500               |   8.34  |   16.6  |   99% |
|3000               |  16.8   |   36.8  |  119% |
|3500               |  33.3   |  68.6   |  106% |
|4000               |  57.2   | 121     |  111% |
|4500               | 105     | 214     |  104% |
|5000               | 171     | 363     |  112% |
+===================+=========+=========+=======+

TEST2: Time (secs) to intersect multiple polygon ELLIPSES.
+===================+=========+=========+=======+
|No. Ellipses       | New     | Old     | Perf. |
|(each)             | Clipper | Clipper | Incr. |
+===================+=========+=========+=======+
|1000               |  0.45   |  0.87   | 93%   |
|2000               |  5.01   |  9.54   | 90%   |
|2500               | 12.57   | 21.33   | 70%   |
|3000               | 27.90   | 48.16   | 73%   |
+===================+=========+=========+=======+
Paths approximating ellipses are such that the edges deviate from their true 
elliptical paths by <= 1/2px. Random ellipses are bounded by the range 
X:0-800, Y:0-600 where the max. elliptical radii are 1/3 of axis bounds 
and the min. radii is 10.
