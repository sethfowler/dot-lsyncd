lctags.lua
==========

Lsyncd script to update ctags files when files are changed. It requires lsyncd
and exuberant ctags to be installed.

How To Use
==========

To configure the script, create a file called '.lctags-root.lua' in the same
directory as this script containing a single line of the form:

        return '/path/to/root/of/my/code/directory'

The script will then monitor all files and directories under that directory for
any changes. When a change is detected, ctags will be run, and the resulting
tags will be placed in the first '.tags' file the script finds when walking up
the directory tree from the changed file or folder. If no '.tags' file is
found, the tags will not be generated. This means that each project needs to
have its own '.tags' file before the script will start to generate tags for it.

This script runs ctags recursively starting at the location of the '.tags'
file, and it may generate more tags than you intend. You can use a
'.tags.exclude' file to prevent ctags from generating any tags for a given file
or directory. The '.tags.exclude' file should be in the same directory as the
'.tags' file it corresponds to. List the exclusions one per line.
