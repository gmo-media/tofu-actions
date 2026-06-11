---
name: fix-drift
description: Fix infrastructure drift by updating .tf files to match the real-world state shown in a saved plan output. Invoked by the drift-fix-claude action as /fix-drift <dir> <tf_binary> <plan_file>.
arguments: dir tf_binary plan_file
disable-model-invocation: true
---

# CRITICAL INSTRUCTIONS FOR FIXING INFRASTRUCTURE DRIFT
You have been given a critical task to fix infrastructure drift in Terraform/OpenTofu configuration files.
Your goal is to update the .tf files to match the current real-world infrastructure state.

## Important Rules
- NEVER run `$tf_binary apply` even if there is a need to update tfstate. Preserve the existing infrastructure state.
- Only make changes to .tf files and run `$tf_binary plan`.
- Always choose the least destructive approach. Be surgical and precise with your edits.
- NEVER leave the configuration in a state where `$tf_binary plan` would destroy and then recreate a resource (the `-/+` / `+/-` actions, shown as "must be replaced" / "forces replacement"). If one of your edits causes a replacement, revert or rework that edit until no replacement remains (e.g. use a `moved` block instead of renaming a resource). A leftover change that only creates or only destroys a resource is tolerable; a paired destroy-and-create of the same resource is not — the verification gate fails the whole run if one remains.

## Context
- Directory with drift: $dir
- The plan result is in $plan_file

## YOUR MISSION - FOLLOW THESE STEPS EXACTLY:
1. Read the plan and understand the changes
The plan is trying to *revert* the external changes done to the infrastructure.
For example, if the plan shows:
```
~ resource "aws_instance" "example" {
    ~ instance_type = "t3.micro" -> "t2.micro"
}
```
"t3.micro" is the real infrastructure state, while "t2.micro" is what's in our .tf files.
This means a user may have manually changed the instance type from t2.micro to t3.micro, and didn't update the .tf file.
You should update the .tf file to match reality - "t3.micro".

The plan is usually quite verbose with default values.
Try not to be confused by these verbose lines - try to extract only the important changes.

2. Fix the drift
Update .tf files to match the CURRENT REAL INFRASTRUCTURE STATE.
This means: incorporate the external changes into your .tf files.

3. Validate
After making changes, run: `$tf_binary plan` within directory `$dir`.
The plan MUST show "No changes. Your infrastructure matches the configuration."
If there are still differences, continue fixing until plan shows no changes.
