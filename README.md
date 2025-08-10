# tofu-actions

A collection of reusable GitHub Actions and workflows for OpenTofu that makes infrastructure automation simple.
This project provides a lighter alternative to [suzuki-shunsuke/tfaction](https://github.com/suzuki-shunsuke/tfaction),
tailored for specific needs:

- Built exclusively for OpenTofu (Terraform not supported yet)
- Works great with monorepos (manage multiple infrastructure directories in one repository)
- Supports local modules within your repository

For more advanced features or battle-tested solutions,
we recommend checking out suzuki-shunsuke/tfaction.

## Getting Started

### Setting up your configuration

Create a file called `.github/tofu-actions-config.js` in your repository and list your OpenTofu directories.
You must *not* put `./` at the start or `/` at the end.

```js
export default {
  dirs: [
    'dev',
    'prod',
  ]
}
```

### Adding workflow files (Quick start)

Copy the workflow examples from `.github/example-workflows/` to your repository's `.github/workflows` directory.

- Create an `.opentofu-version` file in your repository root
- Update the `dir` options in workflow_dispatch to match your needs

### Understanding the quick start workflows

The `.github/workflows/quickstart-*.yaml` files are ready-to-use opinionated workflows that you can call from other workflows.
They help you get started quickly without writing much code.
If you need something more custom, copy the workflow content and adjust it to your needs.
