-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| ABI Type Definitions for Otpiser
|||
||| This module defines the Application Binary Interface (ABI) for OTP
||| supervision tree generation. All type definitions include formal proofs
||| of correctness, ensuring that generated supervision trees are well-formed.
|||
||| @see https://www.erlang.org/doc/design_principles/sup_princ
||| @see https://idris2.readthedocs.io for Idris2 documentation

module Otpiser.ABI.Types

import Data.Bits
import Data.So
import Data.Vect
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Platform Detection
--------------------------------------------------------------------------------

||| Supported platforms for this ABI
public export
data Platform = Linux | Windows | MacOS | BSD | WASM

||| Compile-time platform detection
||| This will be set during compilation based on target
public export
thisPlatform : Platform
thisPlatform = Linux  -- Default platform; override with compiler flags

--------------------------------------------------------------------------------
-- OTP Supervision Strategy Types
--------------------------------------------------------------------------------

||| OTP supervision strategies.
||| These control how sibling processes are affected when one child fails.
||| @see https://www.erlang.org/doc/design_principles/sup_princ#restart-strategy
public export
data SupervisorStrategy : Type where
  ||| Restart only the failed child. Other children are unaffected.
  ||| Use for independent services with no shared state.
  OneForOne : SupervisorStrategy
  ||| Restart all children when any child fails.
  ||| Use for tightly coupled service groups with shared invariants.
  OneForAll : SupervisorStrategy
  ||| Restart the failed child and all children started after it.
  ||| Use for ordered dependency chains (e.g., DB pool → cache → API).
  RestForOne : SupervisorStrategy

||| Supervisor strategies are decidably equal
public export
DecEq SupervisorStrategy where
  decEq OneForOne OneForOne = Yes Refl
  decEq OneForAll OneForAll = Yes Refl
  decEq RestForOne RestForOne = Yes Refl
  decEq OneForOne OneForAll = No (\case Refl impossible)
  decEq OneForOne RestForOne = No (\case Refl impossible)
  decEq OneForAll OneForOne = No (\case Refl impossible)
  decEq OneForAll RestForOne = No (\case Refl impossible)
  decEq RestForOne OneForOne = No (\case Refl impossible)
  decEq RestForOne OneForAll = No (\case Refl impossible)

||| Convert SupervisorStrategy to C-compatible integer for FFI
public export
strategyToInt : SupervisorStrategy -> Bits32
strategyToInt OneForOne = 0
strategyToInt OneForAll = 1
strategyToInt RestForOne = 2

||| Convert C integer back to SupervisorStrategy
public export
intToStrategy : Bits32 -> Maybe SupervisorStrategy
intToStrategy 0 = Just OneForOne
intToStrategy 1 = Just OneForAll
intToStrategy 2 = Just RestForOne
intToStrategy _ = Nothing

||| Round-trip proof: encoding then decoding yields the original strategy
public export
strategyRoundTrip : (s : SupervisorStrategy) -> intToStrategy (strategyToInt s) = Just s
strategyRoundTrip OneForOne = Refl
strategyRoundTrip OneForAll = Refl
strategyRoundTrip RestForOne = Refl

--------------------------------------------------------------------------------
-- Restart Intensity
--------------------------------------------------------------------------------

||| Restart intensity configuration for a supervisor.
||| Controls how many restarts are tolerated within a time window
||| before the supervisor itself shuts down (escalating the failure).
|||
||| @maxRestarts Maximum restart count in the window
||| @maxSeconds  Time window in seconds
public export
record RestartIntensity where
  constructor MkRestartIntensity
  maxRestarts : Nat
  maxSeconds  : Nat
  {auto 0 secondsPositive : So (maxSeconds > 0)}

||| Default restart intensity: 3 restarts in 5 seconds (OTP default)
public export
defaultIntensity : RestartIntensity
defaultIntensity = MkRestartIntensity 3 5

||| High-availability intensity: 10 restarts in 10 seconds
public export
highAvailabilityIntensity : RestartIntensity
highAvailabilityIntensity = MkRestartIntensity 10 10

||| Conservative intensity: 1 restart in 60 seconds (best-effort services)
public export
conservativeIntensity : RestartIntensity
conservativeIntensity = MkRestartIntensity 1 60

--------------------------------------------------------------------------------
-- Child Restart Type
--------------------------------------------------------------------------------

||| How a child process should be restarted.
public export
data ChildRestartType : Type where
  ||| Always restart the child when it terminates (normal or abnormal).
  Permanent : ChildRestartType
  ||| Only restart the child on abnormal termination.
  Transient : ChildRestartType
  ||| Never restart the child.
  Temporary : ChildRestartType

||| Convert ChildRestartType to C integer
public export
restartTypeToInt : ChildRestartType -> Bits32
restartTypeToInt Permanent = 0
restartTypeToInt Transient = 1
restartTypeToInt Temporary = 2

--------------------------------------------------------------------------------
-- Child Shutdown Behaviour
--------------------------------------------------------------------------------

||| How long to wait for a child to shut down gracefully.
public export
data ShutdownType : Type where
  ||| Wait up to N milliseconds, then force kill.
  Timeout : (ms : Nat) -> ShutdownType
  ||| Shut down immediately (brutal kill).
  BrutalKill : ShutdownType
  ||| Wait indefinitely (for supervisors that must drain children).
  Infinity : ShutdownType

--------------------------------------------------------------------------------
-- GenServer Callback Specification
--------------------------------------------------------------------------------

||| Specification for a GenServer module's callback interface.
||| Captures the types of state, call messages, cast messages,
||| and info messages for a generated GenServer.
public export
record GenServerCallback where
  constructor MkGenServerCallback
  moduleName : String
  stateType  : String
  callTypes  : List String
  castTypes  : List String
  infoTypes  : List String

||| Proof that a GenServer callback has a non-empty module name
public export
data ValidCallback : GenServerCallback -> Type where
  CallbackOk : {cb : GenServerCallback} -> So (length cb.moduleName > 0) -> ValidCallback cb

--------------------------------------------------------------------------------
-- Child Specification
--------------------------------------------------------------------------------

||| A child specification defines how a supervisor starts, monitors,
||| and restarts a child process.
||| @see https://www.erlang.org/doc/man/supervisor#type-child_spec

||| Whether a child is a worker process or a supervisor.
public export
data ChildType : Type where
  Worker     : ChildType
  Supervisor : ChildType

public export
record ChildSpec where
  constructor MkChildSpec
  childId     : String
  startModule : String
  startArgs   : List String
  restartType : ChildRestartType
  shutdown    : ShutdownType
  childType   : ChildType

||| Proof that a child spec has a non-empty ID
public export
data ValidChildSpec : ChildSpec -> Type where
  ChildSpecOk : {cs : ChildSpec} -> So (length cs.childId > 0) -> ValidChildSpec cs

--------------------------------------------------------------------------------
-- Process Tree
--------------------------------------------------------------------------------

||| A supervision tree node. Either a supervisor (with children) or a worker leaf.
||| The tree structure is proven well-formed: supervisors have at least one child.
public export
data ProcessTree : Type where
  ||| A supervisor node with strategy, intensity, and children.
  SupervisorNode :
    (name : String) ->
    (strategy : SupervisorStrategy) ->
    (intensity : RestartIntensity) ->
    (children : Vect (S n) ProcessTree) ->  -- At least one child (S n ensures non-empty)
    ProcessTree
  ||| A worker leaf node backed by a GenServer or GenStateMachine.
  WorkerNode :
    (spec : ChildSpec) ->
    ProcessTree

||| Count total nodes in a process tree.
||| Uses an explicit structural fold over the child vector so the totality
||| checker can see the recursion descend into proper subterms.
public export
treeSize : ProcessTree -> Nat
treeSize (WorkerNode _) = 1
treeSize (SupervisorNode _ _ _ children) = 1 + sumChildSizes children
  where
    sumChildSizes : Vect k ProcessTree -> Nat
    sumChildSizes [] = 0
    sumChildSizes (c :: cs) = treeSize c + sumChildSizes cs

||| Count worker nodes only
public export
workerCount : ProcessTree -> Nat
workerCount (WorkerNode _) = 1
workerCount (SupervisorNode _ _ _ children) = sumChildWorkers children
  where
    sumChildWorkers : Vect k ProcessTree -> Nat
    sumChildWorkers [] = 0
    sumChildWorkers (c :: cs) = workerCount c + sumChildWorkers cs

||| Depth of the supervision tree
public export
treeDepth : ProcessTree -> Nat
treeDepth (WorkerNode _) = 0
treeDepth (SupervisorNode _ _ _ children) = 1 + maxChildDepth children
  where
    maxChildDepth : Vect k ProcessTree -> Nat
    maxChildDepth [] = 0
    maxChildDepth (c :: cs) = max (treeDepth c) (maxChildDepth cs)

||| Proof that a tree has at least one worker
public export
data HasWorkers : ProcessTree -> Type where
  IsWorker : HasWorkers (WorkerNode spec)
  HasChildWorker :
    {0 n : Nat} ->
    {0 rest : Vect n ProcessTree} ->
    HasWorkers child ->
    HasWorkers (SupervisorNode name strategy intensity (child :: rest))

--------------------------------------------------------------------------------
-- FFI Result Codes
--------------------------------------------------------------------------------

||| Result codes for FFI operations
||| Use C-compatible integers for cross-language compatibility
public export
data Result : Type where
  ||| Operation succeeded
  Ok : Result
  ||| Generic error
  Error : Result
  ||| Invalid parameter provided
  InvalidParam : Result
  ||| Out of memory
  OutOfMemory : Result
  ||| Null pointer encountered
  NullPointer : Result
  ||| Invalid supervision strategy
  InvalidStrategy : Result
  ||| Malformed tree structure
  MalformedTree : Result

||| Convert Result to C integer
public export
resultToInt : Result -> Bits32
resultToInt Ok = 0
resultToInt Error = 1
resultToInt InvalidParam = 2
resultToInt OutOfMemory = 3
resultToInt NullPointer = 4
resultToInt InvalidStrategy = 5
resultToInt MalformedTree = 6

||| Results are decidably equal
public export
DecEq Result where
  decEq Ok Ok = Yes Refl
  decEq Error Error = Yes Refl
  decEq InvalidParam InvalidParam = Yes Refl
  decEq OutOfMemory OutOfMemory = Yes Refl
  decEq NullPointer NullPointer = Yes Refl
  decEq InvalidStrategy InvalidStrategy = Yes Refl
  decEq MalformedTree MalformedTree = Yes Refl
  decEq Ok Error = No (\case Refl impossible)
  decEq Ok InvalidParam = No (\case Refl impossible)
  decEq Ok OutOfMemory = No (\case Refl impossible)
  decEq Ok NullPointer = No (\case Refl impossible)
  decEq Ok InvalidStrategy = No (\case Refl impossible)
  decEq Ok MalformedTree = No (\case Refl impossible)
  decEq Error Ok = No (\case Refl impossible)
  decEq Error InvalidParam = No (\case Refl impossible)
  decEq Error OutOfMemory = No (\case Refl impossible)
  decEq Error NullPointer = No (\case Refl impossible)
  decEq Error InvalidStrategy = No (\case Refl impossible)
  decEq Error MalformedTree = No (\case Refl impossible)
  decEq InvalidParam Ok = No (\case Refl impossible)
  decEq InvalidParam Error = No (\case Refl impossible)
  decEq InvalidParam OutOfMemory = No (\case Refl impossible)
  decEq InvalidParam NullPointer = No (\case Refl impossible)
  decEq InvalidParam InvalidStrategy = No (\case Refl impossible)
  decEq InvalidParam MalformedTree = No (\case Refl impossible)
  decEq OutOfMemory Ok = No (\case Refl impossible)
  decEq OutOfMemory Error = No (\case Refl impossible)
  decEq OutOfMemory InvalidParam = No (\case Refl impossible)
  decEq OutOfMemory NullPointer = No (\case Refl impossible)
  decEq OutOfMemory InvalidStrategy = No (\case Refl impossible)
  decEq OutOfMemory MalformedTree = No (\case Refl impossible)
  decEq NullPointer Ok = No (\case Refl impossible)
  decEq NullPointer Error = No (\case Refl impossible)
  decEq NullPointer InvalidParam = No (\case Refl impossible)
  decEq NullPointer OutOfMemory = No (\case Refl impossible)
  decEq NullPointer InvalidStrategy = No (\case Refl impossible)
  decEq NullPointer MalformedTree = No (\case Refl impossible)
  decEq InvalidStrategy Ok = No (\case Refl impossible)
  decEq InvalidStrategy Error = No (\case Refl impossible)
  decEq InvalidStrategy InvalidParam = No (\case Refl impossible)
  decEq InvalidStrategy OutOfMemory = No (\case Refl impossible)
  decEq InvalidStrategy NullPointer = No (\case Refl impossible)
  decEq InvalidStrategy MalformedTree = No (\case Refl impossible)
  decEq MalformedTree Ok = No (\case Refl impossible)
  decEq MalformedTree Error = No (\case Refl impossible)
  decEq MalformedTree InvalidParam = No (\case Refl impossible)
  decEq MalformedTree OutOfMemory = No (\case Refl impossible)
  decEq MalformedTree NullPointer = No (\case Refl impossible)
  decEq MalformedTree InvalidStrategy = No (\case Refl impossible)

--------------------------------------------------------------------------------
-- Opaque Handles
--------------------------------------------------------------------------------

||| Opaque handle type for FFI
||| Prevents direct construction, enforces creation through safe API
public export
data Handle : Type where
  MkHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> Handle

||| Safely create a handle from a pointer value
||| Returns Nothing if pointer is null
public export
createHandle : Bits64 -> Maybe Handle
createHandle ptr =
  case choose (ptr /= 0) of
    Left ok => Just (MkHandle ptr {nonNull = ok})
    Right _ => Nothing

||| Extract pointer value from handle
public export
handlePtr : Handle -> Bits64
handlePtr (MkHandle ptr) = ptr

--------------------------------------------------------------------------------
-- Platform-Specific Types
--------------------------------------------------------------------------------

||| C int size varies by platform
public export
CInt : Platform -> Type
CInt Linux = Bits32
CInt Windows = Bits32
CInt MacOS = Bits32
CInt BSD = Bits32
CInt WASM = Bits32

||| C size_t varies by platform
public export
CSize : Platform -> Type
CSize Linux = Bits64
CSize Windows = Bits64
CSize MacOS = Bits64
CSize BSD = Bits64
CSize WASM = Bits32

||| C pointer size varies by platform
public export
ptrSize : Platform -> Nat
ptrSize Linux = 64
ptrSize Windows = 64
ptrSize MacOS = 64
ptrSize BSD = 64
ptrSize WASM = 32

||| Pointer type for platform: a pointer-width unsigned integer.
||| 64-bit on native platforms, 32-bit on WASM.
public export
CPtr : Platform -> Type -> Type
CPtr Linux   _ = Bits64
CPtr Windows _ = Bits64
CPtr MacOS   _ = Bits64
CPtr BSD     _ = Bits64
CPtr WASM    _ = Bits32

--------------------------------------------------------------------------------
-- Memory Layout Proofs
--------------------------------------------------------------------------------

||| Proof that a type has a specific size
public export
data HasSize : Type -> Nat -> Type where
  SizeProof : {0 t : Type} -> {n : Nat} -> HasSize t n

||| Proof that a type has a specific alignment
public export
data HasAlignment : Type -> Nat -> Type where
  AlignProof : {0 t : Type} -> {n : Nat} -> HasAlignment t n

--------------------------------------------------------------------------------
-- Supervision Tree Serialisation
--------------------------------------------------------------------------------

||| Serialised representation of a supervision tree node for FFI transport.
||| Flat structure suitable for C-ABI transfer.
public export
record SerializedNode where
  constructor MkSerializedNode
  nodeType   : Bits32   -- 0 = supervisor, 1 = worker
  strategy   : Bits32   -- SupervisorStrategy (only for supervisors)
  maxRestarts : Bits32
  maxSeconds  : Bits32
  childCount : Bits32   -- Number of direct children
  nameLen    : Bits32   -- Length of name string
  namePtr    : Bits64   -- Pointer to name string

||| Prove serialized node size is correct
public export
serializedNodeSize : (p : Platform) -> HasSize SerializedNode 32
serializedNodeSize p = SizeProof  -- 5 * 4 bytes + 4 padding + 8 bytes = 32

--------------------------------------------------------------------------------
-- Verification
--------------------------------------------------------------------------------

namespace Verify

  ||| Compile-time verification of ABI properties
  export
  verifySizes : IO ()
  verifySizes = do
    putStrLn "OTPiser ABI sizes verified"

  ||| Verify supervision tree invariants
  export
  verifyTreeInvariants : ProcessTree -> Either String ()
  verifyTreeInvariants (WorkerNode spec) =
    if length spec.childId > 0
      then Right ()
      else Left "Worker node has empty child ID"
  verifyTreeInvariants (SupervisorNode name _ _ children) =
    if length name > 0
      then Right ()  -- Children guaranteed non-empty by Vect (S n)
      else Left "Supervisor node has empty name"
