libwinery_sources = [
    'runners.vala',
    'prefix.vala',
    'repos.vala',
    'github.vala',
    'utils.vala',
    'winetricks.vala',
    'registry.vala',
    'errors.vala',
]

libwinery_deps = [
    dependency('gee-0.8'),
    dependency('libsoup-3.0'),
    dependency('gio-2.0'),
    dependency('json-glib-1.0'),
    dependency('libarchive'),
]

pub_libwinery_deps = [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
]

libwinery = library(
    proj_name,
    libwinery_sources,
    dependencies: libwinery_deps,
    install: true,
    install_vala_vapi: true,
    install_vala_header: true,
)

import('pkgconfig').generate(
    libwinery,
    name: proj_name,
    filebase: proj_name,
    version: meson.project_version(),
    requires: pub_libwinery_deps,
    install_dir: get_option('libdir') / 'pkgconfig',
)

libwinery_dep = declare_dependency(
	link_with: libwinery,
)