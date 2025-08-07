# tofu-actions

[suzuki-shunsuke/tfaction](https://github.com/suzuki-shunsuke/tfaction) の再発明な気がしますが、
シンプルさのために自分たちで使うユースケースを切り出しています。

重点的なサポート
- monorepo (1リポジトリ内に複数tfstateディレクトリ)
- local-path modules

より複雑なことがしたくなった場合、上のようなメンテナンス & 信頼されている手法を検討してください。

## 使い方

### PRでplanを行う

`ci.yaml`
```yaml
name: CI

on:
  pull_request:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref_name }}
  cancel-in-progress: false

env:
  AWS_REGION: ap-northeast-1
  TOFU_VERSION : 1.10.4

jobs:
  format:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: ${{ env.TOFU_VERSION }}
      - run: tofu fmt -recursive -check

  prepare:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - id: prepare
        uses: gmo-media/tofu-actions/prepare@v1
    outputs:
      strategy: ${{ steps.prepare.outputs.strategy }}

  plan:
    needs: [ prepare ]
    name: Plan (${{ matrix.dir }})
    if: ${{ needs.prepare.outputs.strategy != '[]' }}
    strategy:
      fail-fast: false
      matrix:
        include: ${{ fromJSON(needs.prepare.outputs.strategy) }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: ${{ env.TOFU_VERSION }}
      - uses: gmo-media/tofu-actions/setup-aws-credentials@v1
        with:
          aws_credentials: ${{ secrets.AWS_CREDENTIALS }}
      - uses: gmo-media/tofu-actions/plan@v1
        with:
          dir: ${{ matrix.dir }}

  plan-comment:
    needs: [ prepare, plan ]
    if: ${{ always() }}
    name: Plan comment
    runs-on: ubuntu-latest
    steps:
      - uses: gmo-media/tofu-actions/plan-comment@v1
```

### マージ後にapplyを行う

`auto-apply.yaml`
```yaml
name: Auto apply

on:
  pull_request:
    branches:
      - master
    types:
      - closed

concurrency:
  group: ${{ github.workflow }}-${{ github.ref_name }}
  cancel-in-progress: false

jobs:
  prepare:
    runs-on: ubuntu-latest
    if: github.event.pull_request.merged == true
    steps:
      - uses: actions/checkout@v4
      - id: prepare
        uses: gmo-media/tofu-actions/prepare@v1
      - id: get-run-id
        uses: gmo-media/tofu-actions/get-run-id@v1
        with:
          pr-plan-workflow-id: ci.yaml
    outputs:
      strategy: ${{ steps.prepare.outputs.strategy }}
      run-id: ${{ steps.get-run-id.outputs.run-id }}

  auto-apply:
    needs: [ prepare ]
    name: Auto Apply (${{ matrix.dir }})
    if: ${{ needs.prepare.outputs.strategy != '[]' }}
    strategy:
      fail-fast: false
      matrix:
        include: ${{ fromJSON(needs.prepare.outputs.strategy) }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: ${{ env.TOFU_VERSION }}
      - uses: gmo-media/tofu-actions/setup-aws-credentials@v1
        with:
          aws_credentials: ${{ secrets.AWS_CREDENTIALS }}
      - uses: gmo-media/tofu-actions/apply@v1
        with:
          dir: ${{ matrix.dir }}
          run-id: ${{ needs.prepare.outputs.run-id }}
```

### Drift checkを行う

`drift-check.yaml`
```yaml
name: Drift Check

on:
  workflow_dispatch:
  workflow_call:
  schedule:
    - cron: "0 0 * * *"

jobs:
  drift-check:
    strategy:
      fail-fast: false
      matrix:
        dir:
          - dev
          - prod
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: ${{ env.TOFU_VERSION }}
      - uses: gmo-media/tofu-actions/setup-aws-credentials@v1
        with:
          aws_credentials: ${{ secrets.AWS_CREDENTIALS }}
      - id: plan
        uses: gmo-media/tofu-actions/plan@v1
        with:
          dir: ${{ matrix.dir }}
      - uses: gmo-media/tofu-actions/notify-drift@v1
        with:
          dir: ${{ matrix.dir }}
          plan: ${{ steps.plan.outputs.plan }}
          webhook: "https://hooks.slack.com/services/..."
```

### 手動planを行う

`plan.yaml`
```yaml
name: Plan
run-name: Plan (${{ inputs.dir }})

on:
  workflow_dispatch:
    inputs:
      dir:
        description: Directory to run in
        type: choice
        required: true
        default: dev
        options:
          - dev
          - prod
          - ...

env:
  AWS_REGION: ap-northeast-1
  TOFU_VERSION: 1.10.4

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: ${{ env.TOFU_VERSION }}
      - uses: gmo-media/tofu-actions/setup-aws-credentials@v1
        with:
          aws_credentials: ${{ secrets.AWS_CREDENTIALS }}
      - uses: gmo-media/tofu-actions/plan@v1
        with:
          dir: ${{ inputs.dir }}
```

### 手動applyを行う

```yaml
name: Apply
run-name: Apply (${{ inputs.dir }})

on:
  workflow_dispatch:
    inputs:
      dir:
        description: Directory to run in
        type: choice
        required: true
        default: dev
        options:
          - dev
          - prod
          - ...
      run-id:
        description: Actions run ID where plan was generated
        type: string
        required: true

env:
  AWS_REGION: ap-northeast-1
  TOFU_VERSION: 1.10.4

jobs:
  apply:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: ${{ env.TOFU_VERSION }}
      - uses: gmo-media/tofu-actions/setup-aws-credentials@v1
        with:
          aws_credentials: ${{ secrets.AWS_CREDENTIALS }}
      - uses: gmo-media/tofu-actions/apply@v1
        with:
          dir: ${{ inputs.dir }}
          run-id: ${{ inputs.run-id }}
```

## おまけ

### 手動force-unlockを行う

```yaml
name: Force unlock
run-name: Force unlock (${{ inputs.dir }})

on:
  workflow_dispatch:
    inputs:
      dir:
        description: Directory to run in
        type: choice
        required: true
        default: dev
        options:
          - dev
          - prod
          - ...
      lock-id:
        description: Lock ID (see error message of OpenTofu)
        type: string
        required: true

env:
  AWS_REGION: ap-northeast-1
  TOFU_VERSION: 1.10.4

jobs:
  apply:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: ${{ env.TOFU_VERSION }}
      - uses: gmo-media/tofu-actions/setup-aws-credentials@v1
        with:
          aws_credentials: ${{ secrets.AWS_CREDENTIALS }}
      - working-directory: ${{ inputs.dir }}
        run: tofu init --reconfigure
      - working-directory: ${{ inputs.dir }}
        run: tofu force-unlock -force ${{ inputs.lock_id }}
```
