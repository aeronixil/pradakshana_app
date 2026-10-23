{{flutter_js}}
{{flutter_build_config}}

// Version the entrypoint so an older cached main.dart.js cannot hide a release.
// Flutter substitutes this build fingerprint even with --pwa-strategy=none.
const buildVersion = {{flutter_service_worker_version}};
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) {
    build.mainJsPath += '?v=' + buildVersion;
  }
}
// Migrate browsers that already cached the original tree-shaken icon font.
// Revalidate manifests and their fonts before the engine reads them. Subsequent
// requests use Hosting's normal revalidation policy.
async function startApp() {
  try {
    const response = await fetch('assets/FontManifest.json', { cache: 'reload' });
    if (response.ok) {
      const manifest = await response.json();
      await Promise.allSettled(manifest.flatMap(family => family.fonts.map(font =>
        fetch('assets/' + font.asset, { cache: 'reload' }).then(r => r.arrayBuffer())
      )));
    }
  } catch (_) {
    // The engine handles unavailable assets; a failed refresh must not block it.
  }
  _flutter.loader.load();
}
startApp();
