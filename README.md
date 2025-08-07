# tofu-actions

[suzuki-shunsuke/tfaction](https://github.com/suzuki-shunsuke/tfaction) の再発明な気がしますが、
シンプルさのために自分たちで使うユースケースを切り出しています。

重点的なサポート
- monorepo (1リポジトリ内に複数tfstateディレクトリ)
- local-path modules

より複雑なことがしたくなった場合、上のようなメンテナンス & 信頼されている手法を検討してください。

## 使い方

### 設定ファイル

`.github/tofu-actions-config.js` を設置し、terraformのディレクトリ一覧を記述してください。

```js
export default {
  dirs: [
    'dev',
    'prod',
  ]
}
```

### Workflowファイル

`.github/example-workflows/` 以下のファイルを参照してください。
