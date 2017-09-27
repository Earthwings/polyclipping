
This is a preview of a major Clipper update that's progressing slowly. While the 
code in previous versions was functional, in many places it is/was downright 
ugly. This new version is a significant rewrite that should be easier to 
understand and maintain. There's also some performance improvement. However, 
currently this new version performs clipping without any merging or simplifying 
of polygons with common/touching edges in clipping solutions. (This was always 
incomplete in previous versions). The 'offsetting' code has also undergone 
significant revision.


There are quite a few changes to Clipper's interface. Notable ones include ...
1. The PolyFillType enumeration has been renamed FillRule (or TFillRule).
2. The cInt type has been replaced with the native 64bit integer type (Int64 
   or int64_t) as there's no longer a need to restrict the range of 64bit path 
   coordinates.
3. The IntPoint and IntRect types have also been renamed Point64 and Rect64
   respectively (or TPoint64 and TRect64 in Delphi).
4. The Clipper object's Execute parameters have changed: an (optional) OpenPaths
   parameter has been added; also, there's now only one FillRule parameter. (On 
   reflection it seemed unnecessary and confusing to provide different fill 
   rules for Subject and Clip paths.)
5. The Polytree class now contains only closed paths (ie polygons) since open 
   paths can't contain/own polygons. (Open paths are now returned via a 
   separate parameter in the Clipper object's Execute method.)
6. The optional Closed parameter in the AddPath and AddPaths methods has changed 
   to IsOpen (and defaults to false).

   
When I originally translated the Library from Delphi (Pascal) to C# and C++,
I deliberately kept a strong Delphi naming style as I thought this would help
with maintenance. In hindsight this was a mistake. It didn't really achieve
that goal, and it made the C# and C++ code look odd. With this new version, 
I've attempted to adopt a more conventional naming style for each languages, 
while admitting that I still have limited coding experience in C# and C++.


Below I've benchmarked some comparisons between the old and the new versions of
Clipper. (I also removed the polygon 'merging' code from the old version so 
we're comparing 'apples with apples'.) All tests were performed on a Windows 10 
64Bit PC with Intel i7 2.0GHz CPU & 8GB RAM.

Tests 1a and 2 reflect Delphi code (compiled to 32bit using Delphi 10.1).Test 
1b reflects C# code (compiled to 64bit .NET Framework with MSVS Community 2017). 
Test 1c reflects C++ code (compiled to 32bit with MSVS Community 2017). 

TEST1a: Time (secs) to intersect 2 COMPLEX polygons - a subject and a clip 
polygon - having random coordinates and varying numbers of edges (Delphi 32bit).
+===================+=========+=========+=======+
|No. Edges          | New     | Old     | Perf. |
|(for each polygon) | Clipper | Clipper | Incr. |  
+===================+=========+=========+=======+
| 100               |   0.002 |   0.003 |  50%  |
| 500               |   0.055 |   0.078 |  42%  |
|1000               |   0.32  |   0.60  |  88%  |
|2000               |   4.17  |   8.15  |  95%  |
|2500               |   9.84  |  20.0   | 103%  |
|3000               |  21.5   |  48.8   | 127%  |
|3500               |  48.7   |  93.5   |  92%  |
|4000               |  94.3   | 173     |  83%  |
|4500               | 183     | 294     |  60%  |
|5000               | 273     | 497     |  82%  |
+===================+=========+=========+=======+
Vertex coordinate ranges X:0-800, Y:0-600 (rounded to nearest 10).

TEST1b: Same test as above but using C# code (to 64bit .NET framework).
+===================+=========+=========+=======+
|No. Edges          | New     | Old     | Perf. |
|(for each polygon) | Clipper | Clipper | Incr. |  
+===================+=========+=========+=======+
| 100               |   0.002 |   0.003 |   50% |   
| 500               |   0.074 |   0.148 |  100% |
|1000               |   0.422 |   0.729 |   73% |
|2000               |   3.87  |   7.34  |   90% |
|2500               |   8.34  |  16.6   |   99% |
|3000               |  16.8   |  36.8   |  119% |
|3500               |  33.3   |  68.6   |  106% |
|4000               |  57.2   | 121     |  111% |
|4500               | 105     | 214     |  104% |
|5000               | 171     | 363     |  112% |
+===================+=========+=========+=======+

TEST1c: Same test as above but using MSVS C++ code (to 32bit).
+===================+=========+=========+=======+
|No. Edges          | New     | Old     | Perf. |
|(for each polygon) | Clipper | Clipper | Incr. |  
+===================+=========+=========+=======+
| 100               |   0.003 |   0.003 |    0% |   
| 500               |   0.054 |   0.084 |   56% |
|1000               |   0.270 |   0.500 |   85% |
|2000               |   1.99  |   4.80  |  141% |
|2500               |   4.64  |  12.1   |  161% |
|3000               |  10.8   |  25.6   |  137% |
|3500               |  21.6   |  55.7   |  158% |
|4000               |  40.9   |  91.3   |  123% |
|4500               |  70.7   | 191     |  170% |
|5000               | 110     | 258     |  135% |
+===================+=========+=========+=======+

TEST2: Time (secs) to intersect multiple polygon ELLIPSES.
+===================+=========+=========+=======+
|No. Ellipses       | New     | Old     | Perf. |
|(each subj & clip) | Clipper | Clipper | Incr. |
+===================+=========+=========+=======+
|1000               |  0.45   |  0.87   | 93%   |
|2000               |  5.01   |  9.54   | 90%   |
|2500               | 12.57   | 21.33   | 70%   |
|3000               | 27.90   | 48.16   | 73%   |
+===================+=========+=========+=======+
Paths approximating ellipses are such that the edges deviate from their true 
elliptical paths by <= 1/2px. Random ellipses are bounded by the range 
X:0-800, Y:0-600 where the max. elliptical radii are 1/3 of axis bounds 
and the min. radii is 10. (Delphi 32bit)
