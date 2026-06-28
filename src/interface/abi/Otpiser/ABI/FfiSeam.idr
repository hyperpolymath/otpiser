-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4: ABI<->FFI Seam Soundness Proofs for Otpiser
|||
||| This module SEALS the seam between the Idris2 ABI and the Zig FFI by
||| proving that every FFI result-code/enum encoder is SOUND:
|||
|||   * Distinct ABI outcomes never collide on the C wire (injectivity).
|||   * The C integer faithfully round-trips back to the ABI value
|||     (faithful / lossless encoding via a total decoder).
|||
||| The estate's STRUCTURAL gate (scripts/abi-ffi-gate.py) checks the Idris
||| and Zig enums agree by name+value. This module supplies the PROOF-SIDE
||| guarantee that the chosen encoding is itself unambiguous and lossless,
||| so the structural agreement is meaningful rather than vacuous.
|||
||| Method: build a total decoder with boolean `Bits32 ==` (which reduces on
||| concrete literals), prove the round-trip by `Refl` per constructor, then
||| DERIVE injectivity from the round-trip via `justInjective` + `cong`.
|||
||| Strict: no believe_me, idris_crash, assert_total, postulate, sorry.

module Otpiser.ABI.FfiSeam

import Otpiser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Generic helper: Just is injective
--------------------------------------------------------------------------------

||| `Just` is injective. Used to peel the `Maybe` wrapper off a round-trip
||| equation so injectivity of the encoder follows from injectivity of the
||| decode-of-encode composite.
public export
justInjective : {0 a : Type} -> {0 x, y : a} -> Just x = Just y -> x = y
justInjective Refl = Refl

--------------------------------------------------------------------------------
-- Result : the primary FFI result-code enum
--------------------------------------------------------------------------------

||| Total decoder: C integer -> Maybe Result.
|||
||| Built with boolean `Bits32 ==` so the comparisons reduce definitionally on
||| concrete literals; this is what lets the round-trip `Refl`s below check.
||| Values match `resultToInt` in Otpiser.ABI.Types exactly.
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just InvalidStrategy
  else if x == 6 then Just MalformedTree
  else Nothing

||| Faithful encoding (theorem b): decoding the encoding of any Result yields
||| back exactly that Result. Discharged constructor-by-constructor by `Refl`
||| because the boolean `==` decoder reduces on the concrete literals.
public export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok = Refl
resultRoundTrip Error = Refl
resultRoundTrip InvalidParam = Refl
resultRoundTrip OutOfMemory = Refl
resultRoundTrip NullPointer = Refl
resultRoundTrip InvalidStrategy = Refl
resultRoundTrip MalformedTree = Refl

||| Encoding is unambiguous (theorem a): distinct ABI Results never collide on
||| the wire. DERIVED from the round-trip: if the two ints are equal then the
||| decodes are equal, and the round-trip identifies each decode with its
||| source Result.
public export
resultToIntInjective : (a, b : Result) -> resultToInt a = resultToInt b -> a = b
resultToIntInjective a b prf =
  justInjective $
    rewrite sym (resultRoundTrip a) in
    rewrite sym (resultRoundTrip b) in
    cong intToResult prf

--------------------------------------------------------------------------------
-- SupervisorStrategy : a further FFI enum encoder (theorem c)
--------------------------------------------------------------------------------
-- Types.idr already provides intToStrategy + strategyRoundTrip. We reuse the
-- round-trip to derive injectivity, sealing this encoder's seam too.

||| Encoding of SupervisorStrategy is unambiguous. Derived from the existing
||| `strategyRoundTrip` in Otpiser.ABI.Types.
public export
strategyToIntInjective : (a, b : SupervisorStrategy)
                      -> strategyToInt a = strategyToInt b -> a = b
strategyToIntInjective a b prf =
  justInjective $
    rewrite sym (strategyRoundTrip a) in
    rewrite sym (strategyRoundTrip b) in
    cong intToStrategy prf

--------------------------------------------------------------------------------
-- ChildRestartType : a further FFI enum encoder (theorem c)
--------------------------------------------------------------------------------
-- Types.idr provides restartTypeToInt but no decoder. We supply the decoder,
-- prove its round-trip, and derive injectivity.

||| Total decoder: C integer -> Maybe ChildRestartType.
||| Values match `restartTypeToInt` in Otpiser.ABI.Types exactly.
public export
intToRestartType : Bits32 -> Maybe ChildRestartType
intToRestartType x =
  if x == 0 then Just Permanent
  else if x == 1 then Just Transient
  else if x == 2 then Just Temporary
  else Nothing

||| Faithful encoding for ChildRestartType.
public export
restartTypeRoundTrip : (t : ChildRestartType)
                    -> intToRestartType (restartTypeToInt t) = Just t
restartTypeRoundTrip Permanent = Refl
restartTypeRoundTrip Transient = Refl
restartTypeRoundTrip Temporary = Refl

||| Encoding of ChildRestartType is unambiguous. Derived from its round-trip.
public export
restartTypeToIntInjective : (a, b : ChildRestartType)
                         -> restartTypeToInt a = restartTypeToInt b -> a = b
restartTypeToIntInjective a b prf =
  justInjective $
    rewrite sym (restartTypeRoundTrip a) in
    rewrite sym (restartTypeRoundTrip b) in
    cong intToRestartType prf

--------------------------------------------------------------------------------
-- Positive controls: concrete decode results, machine-checked by Refl
--------------------------------------------------------------------------------

||| Decoding 0 yields Ok.
public export
decodeOkControl : intToResult 0 = Just Ok
decodeOkControl = Refl

||| Decoding 6 yields MalformedTree (the highest Result code).
public export
decodeMalformedControl : intToResult 6 = Just MalformedTree
decodeMalformedControl = Refl

||| Decoding an out-of-range code yields Nothing (no spurious Result).
public export
decodeOutOfRangeControl : intToResult 7 = Nothing
decodeOutOfRangeControl = Refl

||| Concrete round-trip control for a strategy.
public export
strategyControl : intToStrategy (strategyToInt RestForOne) = Just RestForOne
strategyControl = Refl

||| Concrete round-trip control for a restart type.
public export
restartTypeControl : intToRestartType (restartTypeToInt Transient) = Just Transient
restartTypeControl = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control
--------------------------------------------------------------------------------
-- These witness that the encoding is NOT collapsing distinct outcomes: two
-- DISTINCT result codes have DISTINCT wire integers. Machine-checked: the two
-- primitive Bits32 literals differ, so `Refl` is impossible.

||| Ok and Error do not collide on the wire (resultToInt Ok = 0, Error = 1).
public export
okNotError : Not (resultToInt Ok = resultToInt Error)
okNotError = \case Refl impossible

||| Two distinct higher codes also stay distinct on the wire
||| (NullPointer = 4, MalformedTree = 6).
public export
nullPtrNotMalformed : Not (resultToInt NullPointer = resultToInt MalformedTree)
nullPtrNotMalformed = \case Refl impossible

||| Distinct strategies stay distinct on the wire (OneForOne = 0, RestForOne = 2).
public export
oneForOneNotRestForOne : Not (strategyToInt OneForOne = strategyToInt RestForOne)
oneForOneNotRestForOne = \case Refl impossible
