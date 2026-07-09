{
  uses_user_defaults: true,
  project_name: 'tccx',
  version: '0.0.4',
  keywords: ['apple', 'ios', 'macos', 'reverse engineering', 'sip', 'tcc'],
  description: "Research on Apple's Transparency, Consent & Control (TCC) system.",
  custom_project_badges: [
    {
      anchor: '[![Tests](https://github.com/Tatsh/tccx/actions/workflows/tests.yml/badge.svg)]',
      href: 'https://github.com/Tatsh/tccx/actions/workflows/tests.yml',
    },
    {
      anchor: '[![Coverage Status](https://coveralls.io/repos/github/Tatsh/tccx/badge.svg?branch=master)]',
      href: 'https://coveralls.io/github/Tatsh/tccx?branch=master',
    },
  ],
  license: 'MIT',
  project_type: 'other',
  want_codeql: false,
  want_tests: false,
  cz+: {
    commitizen+: {
      remove_path_prefixes: ['Sources'],
      version_files+: [
        'Package.swift',
        'Sources/tcc-preapprove/Commands.swift',
        'man/tcc-preapprove.1',
        'pyproject.toml',
      ],
    },
  },
  github+: {
    dependabot+: {
      updates+: [
        {
          cooldown: { 'default-days': 7 },
          directory: '/',
          groups: { swift: { patterns: ['*'] } },
          'package-ecosystem': 'swift',
          schedule: { interval: 'weekly' },
        },
        {
          cooldown: { 'default-days': 7 },
          directory: '/',
          groups: {
            development: { 'dependency-type': 'development' },
            production: { 'dependency-type': 'production' },
          },
          'package-ecosystem': 'uv',
          schedule: { interval: 'weekly' },
        },
      ],
    },
  },
  package_json+: {
    private: true,
    cspell+: {
      ignorePaths+: ['.build/**', 'TCC.framework/**', 'tcc.rep/**'],
    },
    prettier+: {
      overrides+: [
        {
          files: ['Package.resolved'],
          options: { parser: 'json' },
        },
      ],
    },
    scripts+: {
      build: 'swift build && codesign --force --sign - --entitlements entitlements.xml .build/debug/tcc-preapprove',
      'build:release': 'swift build -c release --arch arm64 --arch x86_64 && codesign --force --sign - --entitlements entitlements.xml .build/apple/Products/Release/tcc-preapprove',
      'gen-docs': 'uv run sphinx-build --fresh-env --fail-on-warning --builder html --doctree-dir docs/_build/doctrees --define language=en docs docs/_build/html',
      'gen-manpage': 'uv run sphinx-build --fresh-env --fail-on-warning --builder man --doctree-dir docs/_build/doctrees --define language=en docs man',
      qa: 'yarn check-spelling && yarn check-formatting',
      run: 'swift run tcc-preapprove',
      test: 'swift test',
    },
  },
  prettierignore+: [
    // entitlements.xml is an Apple entitlements plist. AMFI's parser (AMFIUnserializeXML) is
    // stricter than XML and rejects Prettier's reformatting (a space in `<true />`, a wrapped
    // DOCTYPE), which makes codesign fail, so it must never be formatted.
    'entitlements.xml',
    '*.swift',
  ],
  gitignore+: [
    '*.framework/',
    '*.xcodeproj',
    '.build/',
    '.swiftpm/',
    '.venv/',
    '/docs/_build/',
    '/man/_static/',
    '__pycache__/',
    'DerivedData/',
    'tccutil',
  ],
  vscode+: {
    settings+: {
      '[swift]': {
        'editor.defaultFormatter': 'swiftlang.swift-vscode',
        'editor.tabSize': 4,
      },
      'files.associations'+: {
        'Package.resolved': 'json',
      },
    },
  },
}
