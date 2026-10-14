# Migration Notes

## Current Requirements

- Ruby 3.3 or newer
- Rails 8.1 or newer
- Recording Studio 4.x (`~> 4.1` in the gemspec; dummy GitHub tag `v4.6.0`)
- Accessible `~> 0.18` (gemspec dependency for `ControllerAuth`; GitHub tag `v0.18.0` until a newer 0.18.x tag ships)
- Root Switchable dummy tag `v0.9.0`
- Metrics dummy tag `v0.2.0` (required by Root Switchable `>= 0.7.0` and Trashable)
- Cache dummy tag `v0.5.0` (required by Root Switchable `>= 0.9.0`)
- Admin dummy tag `v2.3.0` and FlatPack dummy tag `v0.1.207`
- Trashable dummy tag `v0.10.0` (`require: false`; Admin/Accessible query helpers)
- Public RubyGems and GitHub access for dependency installation

## Verification

Install both bundles and run the complete gem and dummy app test path:

```bash
bundle install
BUNDLE_GEMFILE=test/dummy/Gemfile bundle install
bundle exec rake test:all
```

Run the dummy app from its directory for browser verification:

```bash
cd test/dummy
bin/dev
```

Use the [FlatPack repository](https://github.com/bowerbird-app/flatpack) and the live FlatPack demo linked from the top-level README for current component documentation.
