// TEMPORARY: test-only tofu-actions config used to verify the skip-dirs fix for
// nested directory configurations. Will be removed before merging.
export default {
  dirs: {
    'test-fixtures/nested/parent': {},
    'test-fixtures/nested/parent/child': {},
  }
}
