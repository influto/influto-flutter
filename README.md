# InfluTo — Flutter SDKs

Affiliate attribution, referral codes, and store-direct purchase validation for
Flutter apps. This repository is a monorepo containing two published packages
plus a runnable example app.

| Package | pub.dev | What it does |
|---|---|---|
| [`packages/influto`](packages/influto) | [`influto`](https://pub.dev/packages/influto) | Core SDK — attribution, referral-code validation, manual `reportPurchase`, optional RevenueCat hook. |
| [`packages/influto_iap`](packages/influto_iap) | [`influto_iap`](https://pub.dev/packages/influto_iap) | Optional companion — listens to `in_app_purchase` and auto-reports each store purchase, so store-direct apps need no manual reporting. |

## Install

```yaml
dependencies:
  influto: ^1.0.0
  # optional, only for automatic store-direct purchase capture:
  influto_iap: ^1.0.0
```

```dart
import 'package:influto/influto.dart';

await InfluTo.instance.initialize(
  const InfluToConfig(apiKey: 'YOUR_API_KEY'),
);
```

See each package's README for full usage. The canonical wire contract is
[`packages/influto/CONTRACT.md`](packages/influto/CONTRACT.md).

## Repository layout

```
packages/influto/        # the influto package (published)
packages/influto_iap/     # the influto_iap companion (published)
example/                  # reference app (not published) — path-deps both packages
.github/workflows/        # CI + per-package pub.dev publish workflows
```

## Releasing

Each package publishes to pub.dev automatically via OIDC when a matching tag is
pushed (`influto-vX.Y.Z` / `influto_iap-vX.Y.Z`). See the workflow files in
`.github/workflows/` for the per-package release steps.

## License

MIT — see [LICENSE](LICENSE).
