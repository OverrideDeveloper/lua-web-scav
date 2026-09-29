# lua-web-scav

A Lua web resource scavenger for discovering and gathering TXT, XML, and JSON files.

The first grimoire is intentionally small. It uses the vendored
lua-webcall-model as its HTTP/HTTPS transport and keeps discovery policy above
that transport boundary.

## Shape

    seed URL
       |
       v
    lua-web-scav
       |
       +-- fetch
       +-- classify
       +-- discover links
       +-- generate nearby candidates
       +-- collect TXT/XML/JSON
       |
       v
    vendor/lua-webcall-model
       |
       v
    HTTP / HTTPS

The scavenger does not execute JavaScript, maintain browser sessions, or try to
be a general-purpose search engine. It follows resources that can be observed
from fetched content and can generate nearby TXT candidates from what it finds.

## Requirements

- Lua running on Luvit
- Luvit's http, https, and fs modules

No external Lua package is required by the first version.

## Run

The command-line scavenger accepts a starting URL:

    luvit cli https://example.com/

By default it writes gathered resources under scavenged/.

Useful options:

    luvit cli <url> --output <directory> --max-resources <number> --timeout <milliseconds>
    luvit cli <url> --scope <same-site|same-host|any> --allow-host <host>

## Library

    local scav = require("webscav")

    local crawler = scav.new({
        output_dir = "scavenged",
        timeout = 10000,
        max_resources = 100,
    })

    crawler:on("resource", function(resource)
        print(resource.kind, resource.url, resource.path)
    end)

    crawler:start("https://example.com/")

The current resource kinds are:

- txt
- xml
- json

HTML and other navigable responses are fetched for discovery but are not
gathered as resources.

## Discovery

The initial implementation discovers:

- absolute HTTP/HTTPS URLs
- root-relative URLs
- relative paths
- URLs found in common href, src, url, loc, and location attributes/elements
- a small set of nearby TXT filename mutations

Redirects are followed by the scavenger rather than by the transport layer.

### Crawl scope

The default scope is `same-site`. This keeps discovery on the seed site's
hostname/domain family while still allowing common `www` and subdomain
variants, such as `www.example.com`, `example.com`, and
`docs.example.com`. Unrelated domains found in HTML, such as CDN, analytics,
or social-media links, are not queued.

For stricter crawling, use `same-host`:

    luvit cli https://example.com/ --scope same-host

To intentionally permit an additional host while retaining the default
same-site boundary, add `--allow-host`:

    luvit cli https://example.com/ --allow-host downloads.example.net

Use `--scope any` only when unrestricted cross-domain discovery is desired:

    luvit cli https://example.com/ --scope any

The library exposes the same controls through `scope` and `allowed_hosts`.

URL candidates are also rejected when they contain whitespace, template
markers such as `{{ url }}`, malformed HTTP authorities, or unsupported
authority forms. This keeps JavaScript/template artifacts from becoming
crawl targets.

The first implementation uses a lightweight hostname-based same-site rule
rather than bundling the Public Suffix List. Explicit `allowed_hosts` entries
are available when a site needs a cross-domain resource.

The URL mutation behavior is deliberately modest. It is an experiment in
resource neighborhood discovery, not an attempt to guess every possible URL
scheme. The library exposes the mutation function so later experiments can
replace or extend it without changing the transport layer.

## Vendored transport

vendor/lua-webcall-model/ contains the standalone lua-webcall-model transport
used by this repository. It is vendored because there is no deployment
pipeline for resolving the separate library at runtime.

The vendored transport is kept as its own directory and its HTTP/HTTPS behavior
is not mixed into the scavenger.

## License

MIT. See LICENSE.
