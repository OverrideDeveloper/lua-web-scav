# CLI

The CLI is a deliberately thin consumer of webscav.lua.

From the repository root:

    luvit cli https://example.com/

Or from the cli directory:

    luvit init.lua https://example.com/

The crawler prints its fetches and gathered resources and writes gathered
TXT/XML/JSON bodies into the selected output directory.

Use --help for the current command-line options.
