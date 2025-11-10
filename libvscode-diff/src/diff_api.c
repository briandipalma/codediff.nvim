// ============================================================================
// Diff API - Main Entry Point
// ============================================================================
//
// High-level API for diff computation.
// This is the primary interface for Lua/FFI callers.
//
// ============================================================================

#include "diff_api.h"
#include <stdlib.h>

/**
 * Get library version.
 */
const char *diff_api_get_version(void) { return "0.3.0"; }
