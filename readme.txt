Clipper2 (25 January 2017)
This is just a preview of a major update I'm (slowly) working on. 
This new version currently performs only the "bare bones" of the clipping algorithm. 
It's "bare bones" because there's no merging of polygons that have common/touching edges in the clip solutions.
The merging of adjacent/touching polygons is/was incomplete and cumbersome in the earlier versions and needs to be completely rewritten.

Performance is a little faster than earlier versions.
Benchmark test comparison between Old and New Clipper:
+===================+=========+=========+
|Total No. edges    | New     | Old*    |
|(Subject+Clip)^    | Clipper | Clipper |  
+===================+=========+=========+
|4000               | 7.3     |  9.5    |
|5000               | 20.2    |  23.8   |
|6000               | 45.8    |  51.3   |
|7000               | 90      |  115    |
|8000               | 175     |  214    |
|9000               |         |         |
|10000              | 545     |  623    |
+===================+=========+=========+

* Old Clipper is version 6.4.2 (minus code that merges touching solution polygons).
^ Subject & clip polygons each have 1/2 the total edges.

Time (secs) to intersect random subject and clip polygons with vertex coordinate ranges X:0-800, Y:0-600
with each coordinate rounded to nearest 10 to further stress algorithm. 
Test performed on Windows 10 64Bit using Intel i7 2.0GHz CPU, 8GB RAM.
