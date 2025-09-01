# tofu-actions

A collection of reusable GitHub Actions and workflows for OpenTofu that makes infrastructure automation simple.
This project aims to be a simple, opinionated, and easy-to-setup workflow, tailored for specific needs:

- Built exclusively for OpenTofu (Terraform not supported yet)
- Works great with monorepos (manage multiple infrastructure directories in one repository)
- Supports local modules within your repository

For more advanced features or battle-tested solutions, we recommend checking out:
- [shuaibiyy/awesome-tf](https://github.com/shuaibiyy/awesome-tf)
- [suzuki-shunsuke/tfaction](https://github.com/suzuki-shunsuke/tfaction)
- [OP5dev/TF-via-PR](https://github.com/OP5dev/TF-via-PR)
- [dflook/terraform-github-actions](https://github.com/dflook/terraform-github-actions)

See also: [infra-template](https://github.com/gmo-media/infra-template)

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

### Recommended Branch Ruleset

We recommend importing [recommended-ruleset.json](.github/recommended-ruleset.json) to your repository (Settings -> Rules -> Rulesets -> Import a ruleset).

The most important rules here are:
- Require a pull request before merging
- Require status checks to pass before merging (`ci / Plan comment`)
    - Require branches to be up to date before merging

Since applying requires a plan with the *latest* tfstate,
we recommend this ruleset to ensure that the plan on PR is always up to date.
