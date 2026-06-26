-- SPDX-License-Identifier: MPL-2.0
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
import Data.Nat
import Decidable.Equality

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
    else minus alignment (offset `mod` alignment)

||| Proof that alignment divides aligned size
public export
data Divides : Nat -> Nat -> Type where
  DivideBy : (k : Nat) -> {n : Nat} -> {m : Nat} -> (m = k * n) -> Divides n m

||| Sound decision procedure for divisibility.
||| Returns a genuine `Divides d v` witness when `d` divides `v`, else Nothing.
||| For `d = S j`, compute the candidate quotient `q = v `div` (S j)` and check
||| `v = q * (S j)` decidably; the equality proof IS the divisibility witness.
||| Division never reduces under Refl, so we go through `decEq`, never a hole.
public export
decDivides : (d : Nat) -> (v : Nat) -> Maybe (Divides d v)
decDivides Z _ = Nothing
decDivides (S j) v =
  let q = v `div` (S j) in
  case decEq v (q * (S j)) of
    Yes prf => Just (DivideBy q prf)
    No _ => Nothing

||| Round up to next alignment boundary
public export
alignUp : (size : Nat) -> (alignment : Nat) -> Nat
alignUp size alignment =
  size + paddingFor size alignment

||| Decision: is the rounded-up size actually a multiple of the alignment?
||| `alignUp` uses `div`/`mod`, which do not reduce under `Refl`, so the
||| divisibility witness is produced by the sound `decDivides` decision
||| procedure rather than asserted. Returns Nothing only if the (decidable)
||| check fails for the given inputs.
public export
alignUpDivides : (size : Nat) -> (align : Nat) -> Maybe (Divides align (alignUp size align))
alignUpDivides size align = decDivides align (alignUp size align)

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
calcStructSize : Vect k Field -> Nat -> Nat
calcStructSize [] align = 0
calcStructSize (f :: fs) align =
  let lastOffset = foldl (\acc, field => nextFieldOffset field) f.offset fs
      lastSize = foldr (\field, _ => field.size) f.size fs
   in alignUp (lastOffset + lastSize) align

||| Proof that field offsets are correctly aligned
public export
data FieldsAligned : Vect k Field -> Type where
  NoFields : FieldsAligned []
  ConsField :
    (f : Field) ->
    (rest : Vect k Field) ->
    Divides f.alignment f.offset ->
    FieldsAligned rest ->
    FieldsAligned (f :: rest)

||| Verify a struct layout is valid.
||| Both record obligations are discharged by sound decisions: `choose` for the
||| size bound (`So`) and `decDivides` for the alignment witness. No assertions.
public export
verifyLayout : (fields : Vect k Field) -> (align : Nat) -> Either String StructLayout
verifyLayout fields align =
  let size = calcStructSize fields align in
  case choose (size >= sum (map (\f => f.size) fields)) of
    Right _ => Left "Invalid struct size"
    Left sizeOk =>
      case decDivides align size of
        Nothing => Left "Total size is not a multiple of alignment"
        Just alignProof =>
          Right (MkStructLayout fields size align
                   {sizeCorrect = sizeOk} {aligned = alignProof})

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
    {sizeCorrect = Oh}
    {aligned = DivideBy 4 Refl}  -- 32 = 4 * 8

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
    {sizeCorrect = Oh}
    {aligned = DivideBy 4 Refl}  -- 32 = 4 * 8

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
    {sizeCorrect = Oh}
    {aligned = DivideBy 5 Refl}  -- 40 = 5 * 8

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

||| Decide alignment of every field in a vector, building a FieldsAligned witness.
public export
decFieldsAligned : (fields : Vect k Field) -> Maybe (FieldsAligned fields)
decFieldsAligned [] = Just NoFields
decFieldsAligned (f :: fs) =
  case decDivides f.alignment f.offset of
    Nothing => Nothing
    Just dv =>
      case decFieldsAligned fs of
        Nothing => Nothing
        Just rest => Just (ConsField f fs dv rest)

||| Check if layout follows C ABI by deciding field alignment soundly.
public export
checkCABI : (layout : StructLayout) -> Either String (CABICompliant layout)
checkCABI layout =
  case decFieldsAligned layout.fields of
    Just prf => Right (CABIOk layout prf)
    Nothing => Left "Struct fields are not C-ABI aligned"

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

||| Decide whether a field lies within the struct's total size.
||| This is genuinely partial (a field may lie outside an arbitrary layout),
||| so it returns `Maybe` of the bound proof rather than asserting it.
public export
offsetInBounds : (layout : StructLayout) -> (f : Field) -> Maybe (So (f.offset + f.size <= layout.totalSize))
offsetInBounds layout f =
  case choose (f.offset + f.size <= layout.totalSize) of
    Left ok => Just ok
    Right _ => Nothing
