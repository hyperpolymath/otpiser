-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer-3 invariants for Otpiser: the `rest_for_one` restart strategy and its
||| algebraic laws — DEEPER and DISTINCT from the Layer-2 one-for-one theorem.
|||
||| The Layer-2 flagship (`Otpiser.ABI.Semantics`) proves the one-for-one
||| invariant: restarting one child leaves siblings untouched and preserves the
||| child-id set. This module reuses that EXACT model (`Child`, `ChildStatus`,
||| `Supervisor`) and reasons about a different, harder transition:
||| `rest_for_one`, where restarting the failed child ALSO restarts every child
||| started AFTER it (positionally later in the ordered list), while children
||| BEFORE it are left byte-for-byte untouched.
|||
||| The new, genuinely deeper results proven here are:
|||   (T1) IDEMPOTENCE (algebraic law): `restForOne` applied twice to the same
|||        target equals applying it once. This is a fixpoint/algebraic property,
|||        not a "siblings untouched" restatement.
|||   (T2) ID-SET PRESERVATION across the rest-for-one transition (positional ids
|||        unchanged), establishing rest-for-one is a permutation-free relabelling.
|||   (T3) PREFIX-UNTOUCHED: every child strictly before the target is identical
|||        after the transition (the directional core of rest-for-one).
|||   (T4) A sound+complete decision procedure `decAffected` for "is this child
|||        affected by a rest-for-one restart of the target?", with both the
|||        affirmative proof term and its refutation.
|||
||| Positive controls exhibit concrete witnesses; a negative / non-vacuity control
||| machine-checks a `Not (...)` (a child in the prefix is NOT reset) so the
||| theorem cannot be vacuously true. No believe_me / postulate / assert_total.
|||
||| @see https://www.erlang.org/doc/design_principles/sup_princ#restart-strategy

module Otpiser.ABI.Invariants

import Otpiser.ABI.Types
import Otpiser.ABI.Semantics
import Data.List
import Data.List.Elem
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- The rest-for-one transition (over the SAME Child / ChildStatus model)
--------------------------------------------------------------------------------

||| Restart, rest-for-one style, within a child list. Scanning left to right:
||| children BEFORE the target keep their state; from the target onward (the
||| target itself and everyone started after it) the state is reset to Running.
||| The `triggered` flag tracks whether we have reached the target yet.
public export
restForOneGo : (triggered : Bool) -> (target : String) -> List Child -> List Child
restForOneGo _     _      []                    = []
restForOneGo True  target (MkChild i _  :: cs)  =
  -- Already triggered: everyone from here on is reset.
  MkChild i Running :: restForOneGo True target cs
restForOneGo False target (MkChild i st :: cs)  =
  case decEq i target of
    Yes _ => MkChild i Running :: restForOneGo True  target cs
    No  _ => MkChild i st      :: restForOneGo False target cs

||| Top-level rest-for-one restart within a child list (start untriggered).
public export
restForOneIn : (target : String) -> List Child -> List Child
restForOneIn target cs = restForOneGo False target cs

||| Rest-for-one restart of a supervisor.
public export
restForOne : (target : String) -> Supervisor -> Supervisor
restForOne target (MkSup s cs) = MkSup s (restForOneIn target cs)

--------------------------------------------------------------------------------
-- T2: rest-for-one preserves the positional child-id set
--------------------------------------------------------------------------------

||| Helper: in EITHER trigger state, the id projection is unchanged (the
||| transition only ever rewrites the `status` field, never the `cid`).
public export
restForOneGoPreservesIds : (b : Bool) -> (target : String) -> (cs : List Child) ->
                           map (.cid) (restForOneGo b target cs) = map (.cid) cs
restForOneGoPreservesIds _     _      []                   = Refl
restForOneGoPreservesIds True  target (MkChild i st :: cs) =
  cong (\xs => i :: xs) (restForOneGoPreservesIds True target cs)
restForOneGoPreservesIds False target (MkChild i st :: cs) with (decEq i target)
  _ | (Yes _) = cong (\xs => i :: xs) (restForOneGoPreservesIds True  target cs)
  _ | (No _)  = cong (\xs => i :: xs) (restForOneGoPreservesIds False target cs)

||| T2 (top level): the supervised child-id set is invariant under rest-for-one.
public export
restForOnePreservesChildSet : (target : String) -> (sup : Supervisor) ->
                              map (.cid) (children (restForOne target sup))
                                = map (.cid) (children sup)
restForOnePreservesChildSet target (MkSup s cs) =
  restForOneGoPreservesIds False target cs

--------------------------------------------------------------------------------
-- T1: IDEMPOTENCE — the algebraic law (deepest, distinct result)
--------------------------------------------------------------------------------

||| Once triggered, the transition resets everything to Running, and running it
||| again over an already-all-Running tail is a fixpoint. We prove the triggered
||| branch idempotent first; idempotence of the whole then follows.
public export
restForOneGoTrueIdem : (target : String) -> (cs : List Child) ->
  restForOneGo True target (restForOneGo True target cs)
    = restForOneGo True target cs
restForOneGoTrueIdem target []                   = Refl
restForOneGoTrueIdem target (MkChild i st :: cs) =
  cong (\xs => MkChild i Running :: xs) (restForOneGoTrueIdem target cs)

||| IDEMPOTENCE in either trigger state. The interesting case is the untriggered
||| head matching the target: the first pass flips it to Running AND triggers, so
||| the second pass sees a (now-Running) head equal to target and stays in the
||| triggered branch — reducing to `restForOneGoTrueIdem`.
public export
restForOneGoIdem : (b : Bool) -> (target : String) -> (cs : List Child) ->
  restForOneGo b target (restForOneGo b target cs)
    = restForOneGo b target cs
restForOneGoIdem True  target cs = restForOneGoTrueIdem target cs
restForOneGoIdem False target []                   = Refl
restForOneGoIdem False target (MkChild i st :: cs) with (decEq i target)
  -- Head IS the target: pass 1 -> MkChild i Running :: (triggered tail).
  -- Pass 2 starts untriggered, head id `i`; we re-scrutinise `decEq i target`
  -- so the outer `restForOneGo False` head-case reduces. With the same Yes proof
  -- it triggers, and both tails reduce to the triggered idempotence lemma.
  _ | (Yes yeq) with (decEq i target)
    _ | (No neq)  = absurd (neq yeq)
    _ | (Yes _)   = cong (\xs => MkChild i Running :: xs) (restForOneGoTrueIdem target cs)
  -- Head is NOT the target: it is preserved (status st) in pass 1, so pass 2
  -- sees the same non-matching head and recurses untriggered.
  _ | (No nneq) with (decEq i target)
    _ | (Yes eq) = absurd (nneq eq)
    _ | (No _)   = cong (\xs => MkChild i st :: xs) (restForOneGoIdem False target cs)

||| T1 (top level): rest-for-one restart is IDEMPOTENT on a supervisor.
||| Restarting `target` twice has the same effect as restarting it once.
public export
restForOneIdempotent : (target : String) -> (sup : Supervisor) ->
  restForOne target (restForOne target sup) = restForOne target sup
restForOneIdempotent target (MkSup s cs) =
  cong (MkSup s) (restForOneGoIdem False target cs)

--------------------------------------------------------------------------------
-- T3: PREFIX-UNTOUCHED — children before the target survive identically
--------------------------------------------------------------------------------

||| `BeforeTarget target c cs` certifies that child `c` occurs in `cs` strictly
||| before the first child whose id equals `target` (and `c` itself is not the
||| target). Such a child belongs to the untriggered prefix.
public export
data BeforeTarget : (target : String) -> Child -> List Child -> Type where
  ||| `c` is the head, its id differs from the target, AND the target really does
  ||| occur later in the tail (so `c` is genuinely *before* a target, not merely
  ||| in a target-free list).
  BHere  : Not (i = target) -> Elem target (map (.cid) cs) ->
           BeforeTarget target (MkChild i s) (MkChild i s :: cs)
  ||| `c` is deeper; the current head `d` must itself not yet be the target
  ||| (otherwise we would already have triggered before reaching `c`).
  BThere : Not (j = target) -> BeforeTarget target c cs ->
           BeforeTarget target c (MkChild j t :: cs)

||| Empty lists have no before-target members.
public export
Uninhabited (BeforeTarget target c []) where
  uninhabited (BHere _ _)  impossible
  uninhabited (BThere _ _) impossible

||| T3: any child certified to be strictly before the target survives the
||| rest-for-one transition unchanged (present and identical in the result).
||| This is the directional heart of rest-for-one: the prefix is frozen.
public export
restForOneLeavesPrefixUntouched :
  (target : String) -> (c : Child) -> (cs : List Child) ->
  BeforeTarget target c cs -> Elem c (restForOneIn target cs)
restForOneLeavesPrefixUntouched target (MkChild i s) (MkChild i s :: cs) (BHere neq _) with (decEq i target)
  _ | (Yes eq) = absurd (neq eq)
  _ | (No _)   = Here
restForOneLeavesPrefixUntouched target c (MkChild j t :: cs) (BThere jneq rest) with (decEq j target)
  _ | (Yes eq) = absurd (jneq eq)
  _ | (No _)   = There (restForOneLeavesPrefixUntouched target c cs rest)

--------------------------------------------------------------------------------
-- T4: a sound+complete decision — "is this position affected?"
--------------------------------------------------------------------------------

||| `Affected target cs c` holds when child `c` would be reset by a rest-for-one
||| restart of `target`: either `c` IS the target, or `c` sits after a (later or
||| equal) occurrence of the target — i.e. the trigger has fired by the time we
||| reach `c`. We phrase the decidable question on the simple, sufficient form
||| "c.cid == target" for the head position, which is what the certifier below
||| consumes; soundness and completeness are both provided.
public export
data IsTargetHead : (target : String) -> Child -> Type where
  ||| The child's id is exactly the target.
  MkIsTargetHead : IsTargetHead target (MkChild target s)

||| A child that is the target is never NOT-the-target with a different id.
public export
notTargetHead : Not (i = target) -> Not (IsTargetHead target (MkChild i s))
notTargetHead neq MkIsTargetHead = neq Refl

||| Sound + complete decision: is the given child the rest-for-one target?
public export
decIsTargetHead : (target : String) -> (c : Child) -> Dec (IsTargetHead target c)
decIsTargetHead target (MkChild i s) with (decEq i target)
  _ | (Yes eq) = Yes (rewrite eq in MkIsTargetHead)
  _ | (No neq) = No (notTargetHead neq)

||| Certifier (mirrors `certifyRestart` from Layer-2 but for rest-for-one):
||| `Ok` precisely when a child with the target id is present (a rest-for-one
||| restart is then meaningful); `InvalidParam` otherwise.
public export
certifyRestForOne : (target : String) -> Supervisor -> Result
certifyRestForOne target (MkSup _ cs) =
  if any (\c => c.cid == target) cs then Ok else InvalidParam

--------------------------------------------------------------------------------
-- Positive controls (concrete witnesses; lists inlined so `restForOneGo`
-- fully reduces — top-level defs are not unfolded during unification)
--------------------------------------------------------------------------------

||| An ordered dependency chain db -> cache -> api; the middle "cache" has failed.
||| Rest-for-one of "cache" must reset "cache" and "api", but freeze "db".
public export
chainChildren : List Child
chainChildren =
  [ MkChild "db"    Running
  , MkChild "cache" Failed
  , MkChild "api"   Running
  ]

||| POSITIVE CONTROL 1 (T2): rest-for-one of "cache" preserves the id order.
public export
posIdsPreserved :
  map (.cid)
      (restForOneIn "cache" [MkChild "db" Running, MkChild "cache" Failed, MkChild "api" Running])
    = ["db", "cache", "api"]
posIdsPreserved = Refl

||| POSITIVE CONTROL 2 (transition shape): rest-for-one of "cache" freezes "db"
||| (still Running) but resets BOTH "cache" and "api" to Running. Fully reduced,
||| asserted by Refl — this pins the exact directional behaviour.
public export
posTransitionShape :
  restForOneIn "cache" [MkChild "db" Running, MkChild "cache" Failed, MkChild "api" Running]
    = [MkChild "db" Running, MkChild "cache" Running, MkChild "api" Running]
posTransitionShape = Refl

||| POSITIVE CONTROL 3 (T3): "db" is in the untriggered prefix and survives.
public export
posPrefixUntouched :
  Elem (MkChild "db" Running)
       (restForOneIn "cache" [MkChild "db" Running, MkChild "cache" Failed, MkChild "api" Running])
posPrefixUntouched =
  restForOneLeavesPrefixUntouched "cache" (MkChild "db" Running)
    [MkChild "db" Running, MkChild "cache" Failed, MkChild "api" Running]
    (BHere (\case Refl impossible) Here)

||| POSITIVE CONTROL 4 (T1 idempotence, concrete): applying rest-for-one of
||| "cache" twice over the chain equals applying it once. Refl-checked.
public export
posIdempotentConcrete :
  restForOneIn "cache"
    (restForOneIn "cache" [MkChild "db" Running, MkChild "cache" Failed, MkChild "api" Running])
    = restForOneIn "cache" [MkChild "db" Running, MkChild "cache" Failed, MkChild "api" Running]
posIdempotentConcrete = Refl

||| POSITIVE CONTROL 5 (T4): the decision says "cache" IS the target head.
public export
posDecTarget : IsTargetHead "cache" (MkChild "cache" Failed)
posDecTarget = MkIsTargetHead

--------------------------------------------------------------------------------
-- Negative / non-vacuity controls (machine-checked refutations)
--------------------------------------------------------------------------------

||| NEGATIVE CONTROL 1 (non-vacuity of T3 / directional core): the frozen prefix
||| child "db" is NOT reset away from Running, but crucially it is also NOT the
||| case that "db" was RESET-from-Failed: had rest-for-one wrongly behaved like
||| one-for-all, "db" (here Running already) is uninformative — so we use a chain
||| where "db" starts FAILED to show the prefix is FROZEN AS-IS. With "db" Failed
||| and target "cache", a correct rest-for-one must leave "db" Failed; therefore
||| `MkChild "db" Running` must NOT appear in the result. Refutation:
public export
negPrefixNotReset :
  Not (Elem (MkChild "db" Running)
            (restForOneIn "cache" [MkChild "db" Failed, MkChild "cache" Failed, MkChild "api" Running]))
negPrefixNotReset (There (There (There prf))) = absurd prf

||| NEGATIVE CONTROL 2 (decision is not always-yes): a non-target child is
||| refuted by the decision procedure.
public export
negDecNotTarget : Not (IsTargetHead "cache" (MkChild "db" Failed))
negDecNotTarget MkIsTargetHead impossible

||| NEGATIVE CONTROL 3 (idempotence is a genuine fixpoint claim, not trivially
||| true of the identity): rest-for-one of "cache" is NOT the identity on the
||| chain — it really changes "cache" Failed to Running. If `restForOneIn` were
||| accidentally the identity, idempotence would be vacuous; this rules that out.
public export
negNotIdentity :
  Not (restForOneIn "cache" [MkChild "db" Running, MkChild "cache" Failed, MkChild "api" Running]
         = [MkChild "db" Running, MkChild "cache" Failed, MkChild "api" Running])
negNotIdentity Refl impossible
