{{flutter_js}}
{{flutter_build_config}}

// Version the entrypoint so an older cached main.dart.js cannot hide a release.
// Flutter substitutes this build fingerprint even with --pwa-strategy=none.
const buildVersion = '{{flutter_service_worker_version}}';
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) {
    build.mainJsPath += '?v=' + buildVersion;
  }
}
_flutter.loader.load();
