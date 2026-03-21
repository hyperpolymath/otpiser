-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Otpiser
|||
||| This module declares all C-compatible functions that will be
||| implemented in the Zig FFI layer. Functions cover supervision tree
||| generation, OTP code emission, and tree validation.
|||
||| All functions are declared here with type signatures and safety proofs.
||| Implementations live in src/interface/ffi/

module Otpiser.ABI.Foreign

import Otpiser.ABI.Types
import Otpiser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialize the otpiser library.
||| Allocates internal state for tree generation and code emission.
||| Returns a handle to the library instance, or Nothing on failure.
export
%foreign "C:otpiser_init, libotpiser"
prim__init : PrimIO Bits64

||| Safe wrapper for library initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Clean up otpiser library resources.
||| Frees all allocated trees, generated code buffers, and internal state.
export
%foreign "C:otpiser_free, libotpiser"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- Supervision Tree Construction
--------------------------------------------------------------------------------

||| Create a new supervisor node.
||| @handle   Library handle
||| @name     Supervisor module name (Elixir module path)
||| @strategy Supervision strategy (0=one_for_one, 1=one_for_all, 2=rest_for_one)
||| @maxR     Maximum restarts in window
||| @maxS     Maximum seconds for restart window
||| Returns a tree node handle, or null on failure.
export
%foreign "C:otpiser_create_supervisor, libotpiser"
prim__createSupervisor : Bits64 -> String -> Bits32 -> Bits32 -> Bits32 -> PrimIO Bits64

||| Safe wrapper for supervisor creation
export
createSupervisor : Handle -> String -> SupervisorStrategy -> RestartIntensity -> IO (Maybe Handle)
createSupervisor h name strategy intensity = do
  ptr <- primIO (prim__createSupervisor
    (handlePtr h)
    name
    (strategyToInt strategy)
    (cast intensity.maxRestarts)
    (cast intensity.maxSeconds))
  pure (createHandle ptr)

||| Create a worker (GenServer) child node.
||| @handle      Library handle
||| @childId     Unique child identifier
||| @module      Elixir module name for the GenServer
||| @restart     Restart type (0=permanent, 1=transient, 2=temporary)
||| @shutdownMs  Shutdown timeout in milliseconds (0xFFFFFFFF = infinity)
export
%foreign "C:otpiser_create_worker, libotpiser"
prim__createWorker : Bits64 -> String -> String -> Bits32 -> Bits32 -> PrimIO Bits64

||| Safe wrapper for worker creation
export
createWorker : Handle -> ChildSpec -> IO (Maybe Handle)
createWorker h spec = do
  ptr <- primIO (prim__createWorker
    (handlePtr h)
    spec.childId
    spec.startModule
    (restartTypeToInt spec.restartType)
    (shutdownToMs spec.shutdown))
  pure (createHandle ptr)
  where
    shutdownToMs : ShutdownType -> Bits32
    shutdownToMs (Timeout ms) = cast ms
    shutdownToMs BrutalKill = 0
    shutdownToMs Infinity = 0xFFFFFFFF

||| Add a child to a supervisor node.
||| @handle     Library handle
||| @supervisor Handle to the parent supervisor node
||| @child      Handle to the child node (worker or supervisor)
export
%foreign "C:otpiser_add_child, libotpiser"
prim__addChild : Bits64 -> Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for adding a child to a supervisor
export
addChild : Handle -> (supervisor : Handle) -> (child : Handle) -> IO (Either Result ())
addChild h sup child = do
  result <- primIO (prim__addChild (handlePtr h) (handlePtr sup) (handlePtr child))
  pure $ case result of
    0 => Right ()
    n => Left (fromMaybe Error (intToResult n))
  where
    intToResult : Bits32 -> Maybe Result
    intToResult 0 = Just Ok
    intToResult 1 = Just Error
    intToResult 2 = Just InvalidParam
    intToResult 3 = Just OutOfMemory
    intToResult 4 = Just NullPointer
    intToResult 5 = Just InvalidStrategy
    intToResult 6 = Just MalformedTree
    intToResult _ = Nothing
    fromMaybe : a -> Maybe a -> a
    fromMaybe def Nothing = def
    fromMaybe _ (Just x) = x

--------------------------------------------------------------------------------
-- OTP Code Emission
--------------------------------------------------------------------------------

||| Generate Elixir supervision tree code from the constructed tree.
||| @handle   Library handle
||| @treeRoot Handle to the root supervisor node
||| @outDir   Path to output directory for generated .ex files
||| Returns 0 on success, error code on failure.
export
%foreign "C:otpiser_emit_elixir, libotpiser"
prim__emitElixir : Bits64 -> Bits64 -> String -> PrimIO Bits32

||| Safe wrapper for Elixir code emission
export
emitElixir : Handle -> (treeRoot : Handle) -> (outDir : String) -> IO (Either Result ())
emitElixir h root outDir = do
  result <- primIO (prim__emitElixir (handlePtr h) (handlePtr root) outDir)
  pure $ if result == 0 then Right () else Left Error

||| Generate mix.exs project file.
||| @handle    Library handle
||| @appName   OTP application name
||| @outDir    Output directory
export
%foreign "C:otpiser_emit_mix, libotpiser"
prim__emitMix : Bits64 -> String -> String -> PrimIO Bits32

||| Safe wrapper for mix.exs generation
export
emitMix : Handle -> String -> String -> IO (Either Result ())
emitMix h appName outDir = do
  result <- primIO (prim__emitMix (handlePtr h) appName outDir)
  pure $ if result == 0 then Right () else Left Error

||| Generate ExUnit test scaffolding for each GenServer.
||| @handle   Library handle
||| @treeRoot Handle to the root supervisor
||| @outDir   Output directory for test files
export
%foreign "C:otpiser_emit_tests, libotpiser"
prim__emitTests : Bits64 -> Bits64 -> String -> PrimIO Bits32

||| Safe wrapper for test generation
export
emitTests : Handle -> (treeRoot : Handle) -> (outDir : String) -> IO (Either Result ())
emitTests h root outDir = do
  result <- primIO (prim__emitTests (handlePtr h) (handlePtr root) outDir)
  pure $ if result == 0 then Right () else Left Error

--------------------------------------------------------------------------------
-- Tree Validation
--------------------------------------------------------------------------------

||| Validate a supervision tree for correctness.
||| Checks: no cycles, no orphans, valid strategies, consistent child types.
||| @handle   Library handle
||| @treeRoot Handle to the root of the tree
export
%foreign "C:otpiser_validate_tree, libotpiser"
prim__validateTree : Bits64 -> Bits64 -> PrimIO Bits32

||| Safe wrapper for tree validation
export
validateTree : Handle -> (treeRoot : Handle) -> IO (Either Result ())
validateTree h root = do
  result <- primIO (prim__validateTree (handlePtr h) (handlePtr root))
  pure $ if result == 0 then Right () else Left Error

||| Get a human-readable description of the last validation error.
export
%foreign "C:otpiser_validation_error, libotpiser"
prim__validationError : Bits64 -> PrimIO Bits64

||| Safe wrapper for validation error retrieval
export
validationError : Handle -> IO (Maybe String)
validationError h = do
  ptr <- primIO (prim__validationError (handlePtr h))
  if ptr == 0
    then pure Nothing
    else pure (Just (prim__getString ptr))

--------------------------------------------------------------------------------
-- Tree Serialisation (for PanLL visualisation)
--------------------------------------------------------------------------------

||| Serialise a supervision tree to a flat array of SerializedNode structs.
||| Enables PanLL panel rendering and VeriSimDB snapshots.
||| @handle   Library handle
||| @treeRoot Handle to the tree root
||| @outBuf   Pointer to output buffer
||| @bufLen   Buffer capacity in bytes
||| Returns number of nodes written, or 0 on error.
export
%foreign "C:otpiser_serialize_tree, libotpiser"
prim__serializeTree : Bits64 -> Bits64 -> Bits64 -> Bits32 -> PrimIO Bits32

||| Get the required buffer size for serialising a tree.
export
%foreign "C:otpiser_serialized_size, libotpiser"
prim__serializedSize : Bits64 -> Bits64 -> PrimIO Bits32

--------------------------------------------------------------------------------
-- String Operations (shared FFI utilities)
--------------------------------------------------------------------------------

||| Convert C string to Idris String
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

||| Free C string allocated by otpiser
export
%foreign "C:otpiser_free_string, libotpiser"
prim__freeString : Bits64 -> PrimIO ()

--------------------------------------------------------------------------------
-- Error Handling
--------------------------------------------------------------------------------

||| Get last error message
export
%foreign "C:otpiser_last_error, libotpiser"
prim__lastError : PrimIO Bits64

||| Retrieve last error as string
export
lastError : IO (Maybe String)
lastError = do
  ptr <- primIO prim__lastError
  if ptr == 0
    then pure Nothing
    else pure (Just (prim__getString ptr))

||| Get error description for result code
export
errorDescription : Result -> String
errorDescription Ok = "Success"
errorDescription Error = "Generic error"
errorDescription InvalidParam = "Invalid parameter"
errorDescription OutOfMemory = "Out of memory"
errorDescription NullPointer = "Null pointer"
errorDescription InvalidStrategy = "Invalid supervision strategy"
errorDescription MalformedTree = "Malformed supervision tree structure"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:otpiser_version, libotpiser"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get library build info
export
%foreign "C:otpiser_build_info, libotpiser"
prim__buildInfo : PrimIO Bits64

||| Get build information
export
buildInfo : IO String
buildInfo = do
  ptr <- primIO prim__buildInfo
  pure (prim__getString ptr)

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

||| Check if library is initialized
export
%foreign "C:otpiser_is_initialized, libotpiser"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)
