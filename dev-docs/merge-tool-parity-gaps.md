# Merge Tool Diff Rendering - VSCode Parity Gaps

**Date**: 2025-12-09
**Status**: Investigation complete, implementation needed

## Overview

This document tracks the parity gaps between our merge tool diff rendering and VSCode's implementation. Our goal is 100% replication of VSCode's merge editor rendering for the incoming (left/:3) and current (right/:2) editors.

## Architecture Comparison

### VSCode's Flow
1. Compute `base → input1` diff and `base → input2` diff
2. `MappingAlignment.compute()` groups overlapping base ranges
3. For each alignment, `getAlignments()` computes fine-grained line alignments using inner rangeMappings
4. ViewZones (filler lines) inserted based on alignment differences
5. Decorations applied for line highlights and character highlights

### Our Flow
1. Compute `base → input1` diff and `base → input2` diff ✅
2. `compute_mapping_alignments()` groups overlapping base ranges ✅
3. `get_alignments()` computes line alignments ✅
4. Filler lines inserted via extmarks ✅
5. Highlights applied ✅

## Identified Parity Gaps

### Gap 1: RangeMappings Input to getAlignments

**VSCode** (`lineAlignment.ts:21-22`):
```typescript
const equalRanges1 = toEqualRangeMappings(
  m.input1Diffs.flatMap(d => d.rangeMappings),  // All character-level diffs
  m.baseRange.toExclusiveRange(),
  m.input1Range.toExclusiveRange()
);
```

**Our code** (`merge_alignment.lua`):
```lua
local inner1, inner2 = {}, {}
for _, c in ipairs(current_diffs[1]) do
  for _, inner in ipairs(c.inner_changes or {}) do
    table.insert(inner1, inner)
  end
end
```

**Issue**: We collect inner_changes per-mapping, but VSCode flattens ALL rangeMappings across the entire ModifiedBaseRange first. This could affect alignment calculations when multiple mappings exist within one alignment group.

**Fix**: Flatten all inner_changes before passing to `get_alignments()`.

---

### Gap 2: Range Coordinate Format

**VSCode**: Uses `Range.toExclusiveRange()` which returns `{ startLineNumber, startColumn, endLineNumber, endColumn }` with 1-based inclusive start, exclusive end.

**Our code**: Uses `{ start_line, start_col, end_line, end_col }` from C diff library.

**Issue**: Need to verify our C library output matches VSCode's coordinate conventions exactly:
- Line numbers: 1-based ✅
- Start column: 1-based, inclusive ✅
- End column: 1-based, EXCLUSIVE (needs verification)

**Fix**: Add test comparing exact coordinates against VSCode diff output.

---

### Gap 3: toEqualRangeMappings Range Boundaries

**VSCode** (`lineAlignment.ts:72-90`):
```typescript
function toEqualRangeMappings(diffs, inputRange, outputRange) {
  // Starts from inputRange.getStartPosition() / outputRange.getStartPosition()
  // Ends at inputRange.getEndPosition() / outputRange.getEndPosition()
}
```

**Our code**:
```lua
local equal_input_start = { line = input_start, column = 1 }
local equal_output_start = { line = output_start, column = 1 }
-- ...
local equal_input_end = { line = input_end, column = 1 }
```

**Issue**: We hardcode column = 1, but VSCode uses actual range positions which can have different columns at boundaries.

**Fix**: Pass actual range end positions from the containing line range mapping.

---

### Gap 4: Conflict Detection

**VSCode** (`modifiedBaseRange.ts`):
```typescript
public get isConflicting(): boolean {
  return this.input1Diffs.length > 0 && this.input2Diffs.length > 0;
}
```

**Our code** (`merge_alignment.lua`):
```lua
local has_left_changes = #ma.inner1 > 0 or 
  (ma.output1_range.end_line - ma.output1_range.start_line) ~= 
  (ma.base_range.end_line - ma.base_range.start_line)
local has_right_changes = #ma.inner2 > 0 or ...
local is_conflict = has_left_changes and has_right_changes
```

**Issue**: Our heuristic is more complex than needed. A region is conflicting simply if both sides have ANY diffs in that base range.

**Fix**: Simplify to check if both `current_diffs[1]` and `current_diffs[2]` have entries for the alignment.

---

### Gap 5: TextLength Comparison

**VSCode** (`lineAlignment.ts:47`):
```typescript
if (m.length.isGreaterThan(new TextLength(1, 0))) {
```

**Our code**:
```lua
if text_length_is_greater_than(m.length, text_length(1, 0)) then
```

**Issue**: Our `text_length_is_greater_than` implementation needs verification against VSCode's `TextLength.isGreaterThan()`.

**VSCode's logic** (`textLength.ts`):
```typescript
public isGreaterThan(other: TextLength): boolean {
  if (this.lineCount !== other.lineCount) {
    return this.lineCount > other.lineCount;
  }
  return this.columnCount > other.columnCount;
}
```

**Status**: ✅ Our implementation appears correct, but needs test verification.

---

### Gap 6: Highlight Application Scope

**VSCode** (`inputCodeEditorView.ts`): Only highlights changes in CONFLICT regions where both sides modified the same base area.

**Our code**: We do filter for conflict regions, but need to verify the filtering logic matches exactly.

**Fix**: Ensure we only highlight changes that fall within a `MappingAlignment` where both sides have changes.

---

## Verification Checklist

- [ ] Create test case with known VSCode merge scenario
- [ ] Compare exact filler line positions
- [ ] Compare exact highlight ranges (line and character level)
- [ ] Verify edge cases: empty ranges, single-line changes, multi-line changes
- [ ] Test adjacent/touching change merging behavior

## Files to Modify

1. `lua/vscode-diff/render/merge_alignment.lua`
   - Fix inner_changes flattening (Gap 1)
   - Fix range boundary coordinates (Gap 3)
   - Simplify conflict detection (Gap 4)

2. `lua/vscode-diff/render/core.lua`
   - Verify highlight application uses correct ranges

3. `tests/render/merge_alignment_spec.lua`
   - Add coordinate verification tests
   - Add VSCode comparison test cases

## References

- VSCode `lineAlignment.ts`: Core alignment algorithm
- VSCode `viewZones.ts`: Filler line insertion
- VSCode `inputCodeEditorView.ts`: Decoration application
- VSCode `modifiedBaseRange.ts`: Conflict detection
- VSCode `mapping.ts`: MappingAlignment.compute()
