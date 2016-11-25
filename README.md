# torrent.cr [![Build Status](https://travis-ci.org/Papierkorb/torrent.svg?branch=master)](https://travis-ci.org/Papierkorb/torrent)

A BitTorrent client library written in pure Crystal.

Do note that this shard is currently in **BETA**.

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  torrent:
    github: Papierkorb/torrent
```

## Usage

Please see `bin/` for example applications.

## What's missing?

* Improve architecture
* Improve performance (Seeding is fine, leeching is expensive)
* Smarter leech and seed strategies
* Tons of other things
* The planned BEPs
* More tests (Figure out how to best test networking code)

## Implemented BEPs

The index of all BEPs can be found at http://www.bittorrent.org/beps/bep_0000.html

* BEP-0003: The BitTorrent Protocol Specification
* BEP-0005: DHT Protocol (*Experimental*)
* BEP-0006: Fast Extension
* BEP-0010: Extension Protocol
* BEP-0011: Peer Exchange (PEX)
* BEP-0015: UDP Tracker Protocol for BitTorrent (*Except for scraping*)
* BEP-0020: Peer ID Conventions
* BEP-0023: Tracker Returns Compact Peer Lists
* BEP-0027: Private Torrents
* BEP-0041: UDP Tracker Protocol Extensions
* BEP-0048: Tracker Protocol Extension: Scrape

### Planned

* BEP-0009: Extension for Peers to Send Metadata Files
* BEP-0040: Canonical Peer Priority

*All entries are in ascending order of their BEP number*

## Contributing

1. Fork it ( https://github.com/Papierkorb/torrent.cr/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Write tests
4. Commit your changes (git commit -am 'Add some feature')
5. Push to the branch (git push origin my-new-feature)
6. Create a new Pull Request

## Contributors

- [Papierkorb](https://github.com/Papierkorb) Stefan Merettig - creator, maintainer

## Disclaimer

The authors of this library are in no way responsible for any copyright
infiringements caused by using this library or software using this library.
There are many legitimate use-cases for torrents outside of piracy. This library
was written with the intention to be used for such legal purposes.

## License

This library is licensed under the Mozilla Public License 2.0 ("MPL-2").

For a copy of the full license text see the included `LICENSE` file.

For a legally non-binding explanation visit:
[tl;drLegal](https://tldrlegal.com/license/mozilla-public-license-2.0-%28mpl-2%29)
