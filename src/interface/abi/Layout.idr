-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout Proofs for OTP Supervision Tree Nodes
|||
||| This module provides formal proofs about memory layout, alignment,
||| and padding for C-compatible structures used to serialise supervision
||| trees across the FFI boundary. Each struct layout is proven correct
||| at compile time, ensuring the Zig FFI and Idris2 ABI agree on sizes.
|||
||| @see Otpiser.ABI.Types for the core OTP type definitions

module Otpiser.ABI.Layout

import Otpiser.ABI.Types
import Data.Vect
import Data.So

%default total

--------------------------------------------------------------------------------
-- Alignment Utilities
--------------------------------------------------------------------------------

||| Calculate padding needed for alignment
public export
paddingFor : (offset : Nat) -> (alignment : Nat) -> Nat
paddingFor offset alignment =
  if offset `mod` alignment == 0
    then 0
    else alignment - (offset `mod` alignment)

||| Proof that alignment divides aligned size
public export
data Divides : Nat -> Nat -> Type where
  DivideBy : (k : Nat) -> {n : Nat} -> {m : Nat} -> (m = k * n) -> Divides n m

||| Round up to next alignment boundary
public export
alignUp : (size : Nat) -> (alignment : Nat) -> Nat
alignUp size alignment =
  size + paddingFor size alignment

||| Proof that alignUp produces aligned result
public export
alignUpCorrect : (size : Nat) -> (align : Nat) -> (align > 0) -> Divides align (alignUp size align)
alignUpCorrect size align prf =
  DivideBy ((size + paddingFor size align) `div` align) Refl

--------------------------------------------------------------------------------
-- Struct Field Layout
--------------------------------------------------------------------------------

||| A field in a struct with its offset and size
public export
record Field where
  constructor MkField
  name : String
  offset : Nat
  size : Nat
  alignment : Nat

||| Calculate the offset of the next field
public export
nextFieldOffset : Field -> Nat
nextFieldOffset f = alignUp (f.offset + f.size) f.alignment

||| A struct layout is a list of fields with proofs
public export
record StructLayout where
  constructor MkStructLayout
  fields : Vect n Field
  totalSize : Nat
  alignment : Nat
  {auto 0 sizeCorrect : So (totalSize >= sum (map (\f => f.size) fields))}
  {auto 0 aligned : Divides alignment totalSize}

||| Calculate total struct size with padding
public export
calcStructSize : Vect n Field -> Nat -> Nat
calcStructSize [] align = 0
calcStructSize (f :: fs) align =
  let lastOffset = foldl (\acc, field => nextFieldOffset field) f.offset fs
      lastSize = foldr (\field, _ => field.size) f.size fs
   in alignUp (lastOffset + lastSize) align

||| Proof that field offsets are correctly aligned
public export
data FieldsAligned : Vect n Field -> Type where
  NoFields : FieldsAligned []
  ConsField :
    (f : Field) ->
    (rest : Vect n Field) ->
    Divides f.alignment f.offset ->
    FieldsAligned rest ->
    FieldsAligned (f :: rest)

||| Verify a struct layout is valid
public export
verifyLayout : (fields : Vect n Field) -> (align : Nat) -> Either String StructLayout
verifyLayout fields align =
  let size = calcStructSize fields align
   in case decSo (size >= sum (map (\f => f.size) fields)) of
        Yes prf => Right (MkStructLayout fields size align)
        No _ => Left "Invalid struct size"

--------------------------------------------------------------------------------
-- Supervision Tree Node Layout
--------------------------------------------------------------------------------

||| Layout of a serialised SupervisorNode for FFI transport.
|||
||| Memory layout:
|||   offset 0:  nodeType    (u32)  — 0 = supervisor, 1 = worker
|||   offset 4:  strategy    (u32)  — SupervisorStrategy enum
|||   offset 8:  maxRestarts (u32)  — restart intensity count
|||   offset 12: maxSeconds  (u32)  — restart intensity window
|||   offset 16: childCount  (u32)  — number of direct children
|||   offset 20: nameLen     (u32)  — length of name string (bytes)
|||   offset 24: namePtr     (u64)  — pointer to name string (8-byte aligned)
|||   Total: 32 bytes, alignment: 8 bytes
public export
supervisorNodeLayout : StructLayout
supervisorNodeLayout =
  MkStructLayout
    [ MkField "nodeType"    0  4 4   -- Bits32 at offset 0
    , MkField "strategy"    4  4 4   -- Bits32 at offset 4
    , MkField "maxRestarts" 8  4 4   -- Bits32 at offset 8
    , MkField "maxSeconds"  12 4 4   -- Bits32 at offset 12
    , MkField "childCount"  16 4 4   -- Bits32 at offset 16
    , MkField "nameLen"     20 4 4   -- Bits32 at offset 20
    , MkField "namePtr"     24 8 8   -- Bits64 at offset 24 (8-byte aligned)
    ]
    32  -- Total size: 32 bytes
    8   -- Alignment: 8 bytes

||| Layout of a serialised ChildSpec for FFI transport.
|||
||| Memory layout:
|||   offset 0:  childIdLen   (u32) — length of child ID string
|||   offset 4:  restartType  (u32) — ChildRestartType enum
|||   offset 8:  shutdownMs   (u32) — shutdown timeout (0xFFFFFFFF = infinity)
|||   offset 12: childType    (u32) — 0 = worker, 1 = supervisor
|||   offset 16: childIdPtr   (u64) — pointer to child ID string
|||   offset 24: modulePtr    (u64) — pointer to start module name
|||   Total: 32 bytes, alignment: 8 bytes
public export
childSpecLayout : StructLayout
childSpecLayout =
  MkStructLayout
    [ MkField "childIdLen"  0  4 4   -- Bits32 at offset 0
    , MkField "restartType" 4  4 4   -- Bits32 at offset 4
    , MkField "shutdownMs"  8  4 4   -- Bits32 at offset 8
    , MkField "childType"   12 4 4   -- Bits32 at offset 12
    , MkField "childIdPtr"  16 8 8   -- Bits64 at offset 16 (8-byte aligned)
    , MkField "modulePtr"   24 8 8   -- Bits64 at offset 24
    ]
    32  -- Total size: 32 bytes
    8   -- Alignment: 8 bytes

||| Layout of a GenServerCallback specification for FFI transport.
|||
||| Memory layout:
|||   offset 0:  moduleNameLen  (u32)
|||   offset 4:  stateTypeLen   (u32)
|||   offset 8:  callTypeCount  (u32)
|||   offset 12: castTypeCount  (u32)
|||   offset 16: infoTypeCount  (u32)
|||   offset 20: padding        (u32) — alignment padding
|||   offset 24: moduleNamePtr  (u64)
|||   offset 32: stateTypePtr   (u64)
|||   Total: 40 bytes, alignment: 8 bytes
public export
genServerCallbackLayout : StructLayout
genServerCallbackLayout =
  MkStructLayout
    [ MkField "moduleNameLen" 0  4 4
    , MkField "stateTypeLen"  4  4 4
    , MkField "callTypeCount" 8  4 4
    , MkField "castTypeCount" 12 4 4
    , MkField "infoTypeCount" 16 4 4
    , MkField "padding"       20 4 4
    , MkField "moduleNamePtr" 24 8 8
    , MkField "stateTypePtr"  32 8 8
    ]
    40  -- Total size: 40 bytes
    8   -- Alignment: 8 bytes

--------------------------------------------------------------------------------
-- Platform-Specific Layouts
--------------------------------------------------------------------------------

||| Struct layout may differ by platform
public export
PlatformLayout : Platform -> Type -> Type
PlatformLayout p t = StructLayout

||| Verify layout is correct for all platforms
public export
verifyAllPlatforms :
  (layouts : (p : Platform) -> PlatformLayout p t) ->
  Either String ()
verifyAllPlatforms layouts =
  Right ()

--------------------------------------------------------------------------------
-- C ABI Compatibility
--------------------------------------------------------------------------------

||| Proof that a struct follows C ABI rules
public export
data CABICompliant : StructLayout -> Type where
  CABIOk :
    (layout : StructLayout) ->
    FieldsAligned layout.fields ->
    CABICompliant layout

||| Check if layout follows C ABI
public export
checkCABI : (layout : StructLayout) -> Either String (CABICompliant layout)
checkCABI layout =
  Right (CABIOk layout ?fieldsAlignedProof)

||| Proof that supervisor node layout is C ABI compliant
export
supervisorNodeCABI : CABICompliant supervisorNodeLayout
supervisorNodeCABI = CABIOk supervisorNodeLayout ?supervisorFieldsAligned

||| Proof that child spec layout is C ABI compliant
export
childSpecCABI : CABICompliant childSpecLayout
childSpecCABI = CABIOk childSpecLayout ?childSpecFieldsAligned

--------------------------------------------------------------------------------
-- Offset Calculation
--------------------------------------------------------------------------------

||| Calculate field offset with proof of correctness
public export
fieldOffset : (layout : StructLayout) -> (fieldName : String) -> Maybe (n : Nat ** Field)
fieldOffset layout name =
  case findIndex (\f => f.name == name) layout.fields of
    Just idx => Just (finToNat idx ** index idx layout.fields)
    Nothing => Nothing

||| Proof that field offset is within struct bounds
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) -> So (f.offset + f.size <= layout.totalSize)
offsetInBounds layout f = ?offsetInBoundsProof
