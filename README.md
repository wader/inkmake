inkmake
=======

Makefile inspired export from SVG files using Inkscape as backend with some added smartness.

If you're tired of clicking "Export Bitmap…" in Inkscape or you want to automate the process of batch exporting bitmaps or other formats from SVG files then inkmake might be something for you.

With inkmake you describe what you want to export and how using a `Inkfile` and then inkmake takes care of generating the necessary files.

### TL;DR

    # this is a Inkfile

    # will generate duck.png from duck.svg
    duck.png

    # will generate a high resolution duck
    hiresduck.png duck.svg *10

    # will generate files duck.png, duck@2x.png and duck-right.png from animals.svg using area id @duck
    images/duck[@2x|-right=*3,right].png animals.svg @duck

    # output files relative to the parent directory of the Inkfile
    out: ../

    # read SVG files from to the child directory "resources" relative to the Inkfile
    svg: resources
    
### Requirements

Currently only Mac OS X is supported.

On Mac OS X you should only need to install Inkscape. inkmake is written in Ruby and should work with the default Ruby version included in Mac OS X.

### Install

Easiest usage is probably to download and copy `inkmake` to `/usr/local/bin` and make sure executable `chmod a+x /usr/local/bin/inkmake` and is in your shell `PATH` ([howto](http://serverfault.com/questions/16355/how-to-set-global-path-on-os-x/277034#277034)). You can also copy it somewhere else and use the full path when executing it.

### Usage

Default inkmake reads a file called "Inkfile" in the current directory and will read and output files relative to the directory containing the `Inkfile`. But you can both specify the `Inkfile` path as a last argument and also change the SVG source dirctory and output directory using the `--svg` and `--out` argument options.


	Usage: ./inkmake [options] [Inkfile]
	    -v, --verbose                    Verbose output
	    -s, --svg PATH                   SVG source base path
	    -o, --out PATH                   Output base path
	    -f, --force                      Force regenerate (skip time check)
	    -i, --inkscape PATH              Inkscape binary path
	                                     Default: /Applications/Inkscape.app/Contents/Resources/bin/inkscape
	    -h, --help                       Display help

### Inkfile syntax

Each line in a Inkfile describe exports to be made from a SVG file. The basic syntax looks like this:

    # this is comment
    file[variants].ext [options]

Where `variants` and `options` are optional. So in its simplest form a line look like this:

    file.png

And would generate a file called `file.png` from the SVG file `file.svg` using the default resolution of the SVG file.

#### Options

`options` allow you to specify which part of a SVG to export and at which resolution, it also allow you to specify if the output should be rotated in some way.

    duck.png animals.svg @duck *2 right

This would export the area defined by id `duck` from the SVG file `animals.svg` in double resolution and rotate the image 90 degrees clockwise.

All available options:

<table>
	<tr>
		<td><code>path.svg</code></td>
		<td>Source SVG file. Relative to current SVG source path.</td>
	</tr>
	<tr>
		<td><code>123x123, 123in*123in</code></td>
		<td>Set output resolution. Supported units are
			<code>px</code> (absolute pixels, default), 
			<code>pt</code>, 
 			<code>pc</code>, 
 		   	<code>mm</code>, 
 		   	<code>cm</code>, 
 		   	<code>dm</code>, 
 		   	<code>m</code>, 
 		   	<code>in</code>, 
 		   	<code>ft</code> and 
 		   	<code>uu</code> (user units, pixels at 90dpi).
		</td>
	</tr>
	<tr>
		<td><code>*2</code>, <code>*2.5</code></td>
		<td>Scale output when using non-pixel units.</td>
	</tr>
	<tr>
		<td><code>drawing</code></td>
		<td>Export drawing area (default whole page is exported).</td>
	</tr>
	<tr>
		<td><code>@id</code></td>
		<td>Export area defined by <code>id</code>.</td>
	</tr>
	<tr>
		<td><code>@x0:y0:x1:y1</code></td>
		<td>Export specified area. <code>x0:y0</code> is lower left, <code>x1:y1</code> is upper right. In user units.</td>
	</tr>
	<tr>
		<td><code>left</code>, <code>right</code>, <code>upsidedown</code></td>
		<td>Rotate output image, <code>right</code> means 90 degrees clockwise.</td>
	</tr>
	<tr>
		<td><code>png</code>, <code>pdf</code>, <code>ps</code>, <code>eps</code></td>
		<td>Force output format when it can't be determined by the output path.</td>
	</tr>
	<tr>
		<td><code>180dpi</code</td>
		<td>Change dots per inch when rendering non-pixel units (default is 90dpi).</td>
	</tr>
</table>


#### Variants

With variants you can export more than one file with different `options`. This is usefull if you want to export the same SVG or part of a SVG in different resolution or rotations, and it also saves you some typing as you don't need to repeat the output path.

`variants` is a pipe `|` separated list of `name=options` pairs, where `name` is the part of the output path to be used and `options` are options specific to the variant. There is also a shortcut syntax for generating iOS scaled images where you only specify `@2x` as a variant.

     duck[@2x|-right=right|-big=1000x1000].png animals.svg @duck

Would generate the images `duck.png` in resolution specified by id `duck`, `duck@2x.png` in double resolution, `duck-right.png` rotated 90 degrees clockwise and `duck-big.png` in 1000x1000 pixels.

All available variant options:

<table>
	<tr>
		<td><code>left</code>, <code>right</code>, <code>upsidedown</code></td>
		<td>Rotate output image, <code>right</code> means 90 degrees clockwise.</td>
	</tr>
	<tr>
		<td><code>123x123, 123in*123in</code></td>
		<td>Set output resolution. Supported units are
			<code>px</code> (absolute pixels, default), 
			<code>pt</code>, 
 			<code>pc</code>, 
 		   	<code>mm</code>, 
 		   	<code>cm</code>, 
 		   	<code>dm</code>, 
 		   	<code>m</code>, 
 		   	<code>in</code>, 
 		   	<code>ft</code> and 
 		   	<code>uu</code> (user units, pixels at 90dpi).
		</td>
	</tr>
	<tr>
		<td><code>*2</code>, <code>*2.5</code></td>
		<td>Scale output when using non-pixel units.</td>
	</tr>
	<tr>
		<td><code>180dpi</code</td>
		<td>Change dots per inch when rendering non-pixel units (default is 90dpi).</td>
	</tr>
</table>

Special variants:

<table>
	<tr>
		<td><code>@2x</code></td>
		<td>Shortcut for <code>@2x=*2</code>. Usefull when generating iOS scaled images.</td>
	</tr>
</table>

### Paths

Both SVG base path and output base path can be set from the `Inkfile` or with command line arguments. The order of preference is, first command line argument then `Inkfile` `out:`/`svg:` configuration and if non of them is provided the paths fallback to be relative to the `Inkfile`.

### Resolution and units

Resolutions specified in the `Inkfile` without units or as `px` will always be absolute number of pixels in output image and will not change depending on scale and dpi. But note that default the SVG 

If you don't specify any resolution the resolution and units will depend on how its defined in the SVG file. In the case of SVG files saved by Inkscape this is most likely user units which is defined as pixels at 90dpi which inkmake will translate to absolute depending on scale and dpi if specified.

### TODO

 Linux support  
 Windows support  
 Plain SVG output? does not work with areas
