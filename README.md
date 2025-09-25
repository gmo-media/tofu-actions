# tofu-actions

A collection of reusable GitHub Actions and workflows for Terraform/OpenTofu that makes infrastructure automation simple.
This project aims to be a simple, opinionated, and easy-to-setup workflow, tailored for specific needs:

- Works great with monorepos (manage multiple infrastructure directories in one repository)
- Supports local modules within your repository
- Although built primarily for OpenTofu, Terraform should work by passing `tf-binary: 'terraform'` to inputs.

For more advanced features or battle-tested solutions, we recommend checking out:
- [shuaibiyy/awesome-tf](https://github.com/shuaibiyy/awesome-tf)
- [suzuki-shunsuke/tfaction](https://github.com/suzuki-shunsuke/tfaction)
- [OP5dev/TF-via-PR](https://github.com/OP5dev/TF-via-PR)
- [dflook/terraform-github-actions](https://github.com/dflook/terraform-github-actions)

See also: [infra-template](https://github.com/gmo-media/infra-template)

## Getting Started

### Setup configuration file

Create a file called `.github/tofu-actions-config.js` in your repository.
Look at this repository's [.github/tofu-actions-config.js](./.github/tofu-actions-config.js) for syntax.

Configuration example where `./dev/` and `./prod/foo/bar/` contains Terraform codes:
```js
const config = {
  auth: {
    mode: 'aws-oidc',
    awsRegion: 'ap-northeast-1',
    awsPlanRole: '<role arn>',
    awsApplyRole: '<role arn>',
  }
}
export default {
  dirs: {
    'dev': config,
    'prod/foo/bar': config,
  }
}
```

### Add workflow files (Quick start)

Copy the workflow files from `.github/example-workflows/` to your repository's `.github/workflows` directory.
If needed, update the `dir` options in workflow_dispatch.

> [!NOTE]
> The `.github/workflows/quickstart-*.yaml` files are ready-to-use, opinionated workflows that you can call from other workflows.
> They help you get started quickly without writing much code.
>
> If you need something more custom, copy the workflow content and adjust it to your needs.

### Import branch ruleset

We recommend importing [recommended-ruleset.json](.github/recommended-ruleset.json) to your repository (Settings -> Rules -> Rulesets -> Import a ruleset).

The most important rules here are:
- Require a pull request before merging
- Require status checks to pass before merging (`ci / Plan comment`)
    - Require branches to be up to date before merging

To apply with a plan, you need a plan generated with the *latest* tfstate.
We recommend this ruleset to ensure that the plan on PR is always up to date,
because the quickstart-ci workflow will use the latest plan from the PR.
