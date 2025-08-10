# tofu-actions

gmo-media/tofu-actions is a collection of reusable GitHub Actions for OpenTofu.
While being a simpler alternative to [suzuki-shunsuke/tfaction](https://github.com/suzuki-shunsuke/tfaction),
gmo-media/tofu-actions is focused on our use-cases:

- Only supports OpenTofu (and not Terraform) for now
- Monorepo support (multiple tofu directories exist in one repository)
- local-path modules within the repository

If you want to do more advanced stuff or want to rely on battle-tested solutions,
consider a more maintained solution like suzuki-shunsuke/tfaction.

## Installation

### Configuration file

Put `.github/tofu-actions-config.js` in the repository and fill in Terraform directory names within the repository.
Do NOT prefix paths with `./` nor suffix with `/`.

```js
export default {
  dirs: [
    'dev',
    'prod',
  ]
}
```

### Workflow files

You can copy files inside `.github/example-workflows/` and put them under `.github/workflows` of your repository.

- Add `.opentofu-version` file to repository root, as used in example workflows.
- Modify workflow_dispatch's `dir` options and its default, if needed.
