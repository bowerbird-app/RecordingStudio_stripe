# Recording Studio 4.x Template Update

Copied addons now start on Recording Studio 4.x.

- Gemspec: `add_dependency "recording_studio", "~> 4.1"`
- Dummy GitHub tags: Recording Studio `v4.4.0`, Accessible `v0.13.0`, Admin `v2.1.0`, Root Switchable `v0.6.0`, FlatPack `v0.1.207`
- Authenticated dummy layout: `RecordingStudio::UsesDefaultLayout` plus FlatPack CSS/JS
- Hooks and BaseService come from core; do not copy them into a new addon
- Recordable declarations remain required
- Optional example mixin: `include RecordingStudio::Capabilities::Example.to(**opts)` wraps `RecordingStudio::Capabilities.include_for`. Installing the gem does not enable it globally.
