-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-Checked ABI Theorems for Otpiser
|||
||| This module collects the genuine, compiler-verified theorems about the
||| Otpiser C-ABI surface. Each `*Compliant` theorem exhibits a DIRECT
||| `FieldsAligned` witness for a concrete `StructLayout`: one `DivideBy`
||| per field, where `field.offset = k * field.alignment`. Multiplication
||| reduces during type-checking (so `Refl` discharges each equation), whereas
||| division does NOT — hence these witnesses are built by hand rather than via
||| the `decFieldsAligned` decision procedure.
|||
||| The result-code lemmas pin the wire encoding of the FFI `Result` enum.
|||
||| @see Otpiser.ABI.Layout for the layouts and the `CABICompliant` relation
||| @see Otpiser.ABI.Types  for the `Result` encoding

module Otpiser.ABI.Proofs

import Otpiser.ABI.Types
import Otpiser.ABI.Layout
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- C-ABI compliance of the concrete struct layouts
--------------------------------------------------------------------------------

||| The serialised supervisor-node layout is C-ABI compliant: every field's
||| offset is an exact multiple of its alignment.
|||   nodeType@0/4, strategy@4/4, maxRestarts@8/4, maxSeconds@12/4,
|||   childCount@16/4, nameLen@20/4, namePtr@24/8.
export
supervisorNodeCompliant : CABICompliant Layout.supervisorNodeLayout
supervisorNodeCompliant =
  CABIOk Layout.supervisorNodeLayout
    (ConsField _ _ (DivideBy 0 Refl)   -- offset 0  = 0 * 4
    (ConsField _ _ (DivideBy 1 Refl)   -- offset 4  = 1 * 4
    (ConsField _ _ (DivideBy 2 Refl)   -- offset 8  = 2 * 4
    (ConsField _ _ (DivideBy 3 Refl)   -- offset 12 = 3 * 4
    (ConsField _ _ (DivideBy 4 Refl)   -- offset 16 = 4 * 4
    (ConsField _ _ (DivideBy 5 Refl)   -- offset 20 = 5 * 4
    (ConsField _ _ (DivideBy 3 Refl)   -- offset 24 = 3 * 8
    NoFields)))))))

||| The serialised child-spec layout is C-ABI compliant.
|||   childIdLen@0/4, restartType@4/4, shutdownMs@8/4, childType@12/4,
|||   childIdPtr@16/8, modulePtr@24/8.
export
childSpecCompliant : CABICompliant Layout.childSpecLayout
childSpecCompliant =
  CABIOk Layout.childSpecLayout
    (ConsField _ _ (DivideBy 0 Refl)   -- offset 0  = 0 * 4
    (ConsField _ _ (DivideBy 1 Refl)   -- offset 4  = 1 * 4
    (ConsField _ _ (DivideBy 2 Refl)   -- offset 8  = 2 * 4
    (ConsField _ _ (DivideBy 3 Refl)   -- offset 12 = 3 * 4
    (ConsField _ _ (DivideBy 2 Refl)   -- offset 16 = 2 * 8
    (ConsField _ _ (DivideBy 3 Refl)   -- offset 24 = 3 * 8
    NoFields))))))

||| The serialised GenServer-callback layout is C-ABI compliant.
|||   moduleNameLen@0/4, stateTypeLen@4/4, callTypeCount@8/4, castTypeCount@12/4,
|||   infoTypeCount@16/4, padding@20/4, moduleNamePtr@24/8, stateTypePtr@32/8.
export
genServerCallbackCompliant : CABICompliant Layout.genServerCallbackLayout
genServerCallbackCompliant =
  CABIOk Layout.genServerCallbackLayout
    (ConsField _ _ (DivideBy 0 Refl)   -- offset 0  = 0 * 4
    (ConsField _ _ (DivideBy 1 Refl)   -- offset 4  = 1 * 4
    (ConsField _ _ (DivideBy 2 Refl)   -- offset 8  = 2 * 4
    (ConsField _ _ (DivideBy 3 Refl)   -- offset 12 = 3 * 4
    (ConsField _ _ (DivideBy 4 Refl)   -- offset 16 = 4 * 4
    (ConsField _ _ (DivideBy 5 Refl)   -- offset 20 = 5 * 4
    (ConsField _ _ (DivideBy 3 Refl)   -- offset 24 = 3 * 8
    (ConsField _ _ (DivideBy 4 Refl)   -- offset 32 = 4 * 8
    NoFields))))))))

--------------------------------------------------------------------------------
-- Result-code wire-encoding lemmas
--------------------------------------------------------------------------------

||| The success code encodes to 0 (the C convention for "no error").
export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

||| The null-pointer error encodes to 4, distinct from success.
export
nullPointerIsFour : resultToInt NullPointer = 4
nullPointerIsFour = Refl

||| Encoding is injective on the two endpoints we care about most: success and
||| the malformed-tree error never collide. Pins that 0 /= 6 under the encoding.
export
okDistinctFromMalformed : Not (resultToInt Ok = resultToInt MalformedTree)
okDistinctFromMalformed = \case Refl impossible

--------------------------------------------------------------------------------
-- Supervision-strategy round-trip (re-export as a named theorem)
--------------------------------------------------------------------------------

||| Strategy encode/decode is a genuine round trip for every strategy.
export
strategyEncodingRoundTrips :
  (s : SupervisorStrategy) -> intToStrategy (strategyToInt s) = Just s
strategyEncodingRoundTrips = strategyRoundTrip
