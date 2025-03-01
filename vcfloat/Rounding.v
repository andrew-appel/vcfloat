(** VCFloat: A Unified Coq Framework for Verifying C Programs with
 Floating-Point Computations. Application to SAR Backprojection.
 
 Version 1.0 (2015-12-04)
 
 Copyright (C) 2015 Reservoir Labs Inc.
 All rights reserved.
 
 This file, which is part of VCFloat, is free software. You can
 redistribute it and/or modify it under the terms of the GNU General
 Public License as published by the Free Software Foundation, either
 version 3 of the License (GNU GPL v3), or (at your option) any later
 version. A verbatim copy of the GNU GPL v3 is included in gpl-3.0.txt.
 
 This file is distributed in the hope that it will be useful, but
 WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See LICENSE for
 more details about the use and redistribution of this file and the
 whole VCFloat library.
 
 This work is sponsored in part by DARPA MTO as part of the Power
 Efficiency Revolution for Embedded Computing Technologies (PERFECT)
 program (issued by DARPA/CMO under Contract No: HR0011-12-C-0123). The
 views and conclusions contained in this work are those of the authors
 and should not be interpreted as representing the official policies,
 either expressly or implied, of the DARPA or the
 U.S. Government. Distribution Statement "A" (Approved for Public
 Release, Distribution Unlimited.)
 
 
 If you are using or modifying VCFloat in your work, please consider
 citing the following paper:
 
 Tahina Ramananandro, Paul Mountcastle, Benoit Meister and Richard
 Lethin.
 A Unified Coq Framework for Verifying C Programs with Floating-Point
 Computations.
 In CPP (5th ACM/SIGPLAN conference on Certified Programs and Proofs)
 2016.
 
 
 VCFloat requires third-party libraries listed in ACKS along with their
 copyright information.
 
 VCFloat depends on third-party libraries listed in ACKS along with
 their copyright and licensing information.
*)
(**
Author: Tahina Ramananandro <ramananandro@reservoir.com>

VCFloat: core and annotated languages for floating-point operations.
*)

Require Import Interval.Tactic.
From vcfloat Require Export RAux.
From Flocq Require Import Binary Bits Core.
From compcert Require Import lib.IEEE754_extra lib.Floats.
Require compcert.lib.Maps.  
Require Coq.MSets.MSetAVL.
Require vcfloat.Fprop_absolute.
Require Import vcfloat.Float_lemmas.
Set Bullet Behavior "Strict Subproofs".
Global Unset Asymmetric Patterns.

Require Export vcfloat.FPCore vcfloat.FPLang.
Import Bool.

Local Open Scope R_scope.

Module MSET := MSetAVL.Make(Nat).

Class Map (T U M: Type): Type :=
  {
    mget: M -> T -> U;
    mset: M -> T -> U -> M;
    mempty: U -> M;
    mget_set: forall m_T_eq_dec: forall t1 t2: T, {t1 = t2} + {t1 <> t2}, forall
                     m t t' u,
                mget (mset m t u) t' = if m_T_eq_dec t' t then u else mget m t';
    mget_empty: forall t u, mget (mempty u) t = u
  }.

Lemma finite_errors_ex {T M} {MAP: Map nat T M}  (t: T) n:
  forall errors,
  exists m,
    forall i,
      mget m i = if Nat.ltb i n then errors i else t.
Proof.
  induction n; intros.
  {
    exists (mempty t).
    intros.
    rewrite mget_empty.
    reflexivity.
  }
  specialize (IHn errors).
  destruct IHn.
  exists (mset x n (errors n)).
  intros.
  rewrite (mget_set Nat.eq_dec).
  destruct (Nat.eq_dec i n).
  {
    subst.
    rewrite (fun n m => let (_, J) := Nat.ltb_lt n m in J); auto with arith.
  }
  rewrite H.
  replace (Nat.ltb i n) with (Nat.ltb i (S n)); auto.
  rewrite Bool.eq_iff_eq_true.
  repeat rewrite Nat.ltb_lt.
  intuition lia.
Qed.  

Section COMPCERTMAPS.

Class MapIndex (T: Type): Type :=
  {
    index_of_tr: T -> positive;
    index_of_tr_correct:
      forall tr1 tr2,
        (tr1 = tr2) <-> (index_of_tr tr1 = index_of_tr tr2)
  }.

Local Program Instance compcert_map:
  forall T U, MapIndex T -> Map T U (Maps.PMap.t U) :=
  {
    mget m t := Maps.PMap.get (index_of_tr t) m;
    mset m t u := Maps.PMap.set (index_of_tr t) u m;
    mempty := @Maps.PMap.init _
  }.
Solve Obligations with (intros; try apply Maps.PMap.gi). 
   (* Need this line for compatibility with CompCert 3.9 and before and/or Coq 8.13 and before *)
Next Obligation.
    rewrite Maps.PMap.gsspec.
    destruct (Coqlib.peq (index_of_tr t') (index_of_tr t)).
    {
      rewrite <- index_of_tr_correct in e.
      destruct (m_T_eq_dec t' t); congruence.
    }
    rewrite <- index_of_tr_correct in n.
    destruct (m_T_eq_dec t' t); congruence.
Defined.

End COMPCERTMAPS.

Section I_OF_TR.

Lemma some_eq {U} (u1 u2: U):
  (u1 = u2 <-> Some u1 = Some u2).
Proof.
  intuition congruence.
Qed.

Local Program Instance index_of_option T:
  MapIndex T ->
  MapIndex (option T) :=
  {
    index_of_tr := fun o =>
      match o with
        | None => xH
        | Some t => xI (index_of_tr t)
      end
  }.
Next Obligation.
  destruct tr1; destruct tr2; try intuition congruence.
  generalize (index_of_tr_correct t t0).
  rewrite <- some_eq.
  intro K.
  rewrite K.
  intuition congruence.
Defined.

Fixpoint inj_pair_aux (a: positive) (b: positive) {struct a}: positive :=
  match a with
    | xH => b
    | xI a' => inj_pair_aux a' (xO (xI b))
    | xO a' => inj_pair_aux a' (xO (xO b))
  end.

Fixpoint inj_pair_rev_r (b: positive): option positive :=
  match b with
    | xI b' => Some b'
    | xO (xI b') => inj_pair_rev_r b'
    | xO (xO b') => inj_pair_rev_r b'
    | _ => None
  end.

Lemma inj_pair_aux_right_correct a1:
  forall a2 b1 b2,
    inj_pair_aux a1 b1 = inj_pair_aux a2 b2 ->
    forall c1 c2,
    inj_pair_rev_r b1 = Some c1 ->
    inj_pair_rev_r b2 = Some c2 ->
    c1 = c2.
Proof.
  induction a1; simpl; intros; eauto.
  subst b1.
  revert b2 c1 c2 H0 H1.
  induction a2; simpl; intros; eauto.
  congruence.
Qed.

Fixpoint inj_pair_rev_l (a b: positive) {struct b}: positive :=
  match b with
    | xO (xI b') => inj_pair_rev_l (xI a) b'
    | xO (xO b') => inj_pair_rev_l (xO a) b'
    | _ => a
  end.

Lemma inj_pair_aux_left_correct a1:
  forall a2 b1 b2,
    inj_pair_aux a1 b1 = inj_pair_aux a2 b2 ->
    forall c,
      inj_pair_rev_r b1 = Some c ->
      inj_pair_rev_r b2 = Some c ->
      inj_pair_rev_l a1 b1 = inj_pair_rev_l a2 b2
.
Proof.
  induction a1; simpl; intros.
  {
    specialize (IHa1 _ _ _ H).
    simpl in IHa1.
    eauto.
  }
  {
    specialize (IHa1 _ _ _ H).
    simpl in IHa1.
    eauto.
  }
  subst b1.
  revert b2 c H0 H1.
  induction a2; simpl; intros.
  {
    specialize (IHa2 _ _ H0).
    simpl in IHa2.
    eauto.
  }
  {
    specialize (IHa2 _ _ H0).
    simpl in IHa2.
    eauto.
  }
  auto.
Qed.

Definition inj_pair a b := inj_pair_aux a (xI b).

Lemma inj_pair_correct a1 a2 b1 b2:
  (a1, b1) = (a2, b2) <-> inj_pair a1 b1 = inj_pair a2 b2.
Proof.
  split.
  {
    congruence.
  }
  intros.
  specialize (inj_pair_aux_right_correct _ _ _ _ H _ _ (eq_refl _) (eq_refl _)).
  intros; subst.
  specialize (inj_pair_aux_left_correct _ _ _ _ H _ (eq_refl _) (eq_refl _)).
  simpl.
  congruence.
Qed.

Lemma inject_pair {A B} (a1 a2: A) (b1 b2: B):
  a1 = a2 ->
  b1 = b2 ->
  (a1, b1) = (a2, b2)
.
Proof.
  congruence.
Qed.

Lemma inject_pair_iff {A B} (a1 a2: A) (b1 b2: B):
  (a1 = a2 /\ b1 = b2) <-> (a1, b1) = (a2, b2)
.
Proof.
  intuition congruence.
Qed.

Local Program Instance index_of_pair U V:
  MapIndex U ->
  MapIndex V ->
  MapIndex (U * V) :=
  {
    index_of_tr := fun uv =>
                     let '(u, v) := uv in
                     inj_pair (index_of_tr u) (index_of_tr v)
  }.
Next Obligation.
  rewrite <- inj_pair_correct.
  repeat rewrite <- inject_pair_iff.
  repeat rewrite <- index_of_tr_correct.
  tauto.
Defined.

End I_OF_TR.

Section WITHVAR.

Context `{VAR: VarType}.

Context {NANS: Nans}.

Inductive ratom: Type :=
| RConst (_: Defs.float Zaux.radix2)
| RVar (ty: type) (_: V)
| RError (_: nat)
.

Inductive rexpr: Type :=
  | RAtom (_: ratom)
  | RUnop (o: Tree.unary_op) (e: rexpr)
  | RBinop (o: Tree.binary_op) (e1 e2: rexpr)
. 

Fixpoint reval (e: rexpr) (env: forall ty, V -> ftype ty) (eenv: nat -> R): R :=
  match e with
    | RAtom (RConst q) => F2R _ q
    | RAtom (RVar ty n) => B2R _ _ (env ty n)
    | RAtom (RError n) => eenv n
    | RUnop o e => Prog.unary Prog.real_operations o (reval e env eenv)
    | RBinop o e1 e2 => Prog.binary Prog.real_operations o (reval e1 env eenv) (reval e2 env eenv)
  end.

Fixpoint max_error_var (e: rexpr): nat :=
  match e with
    | RAtom (RError n) =>
      S n
    | RUnop _ e => max_error_var e
    | RBinop _ e1 e2 => Nat.max (max_error_var e1) (max_error_var e2)
    | _ => O
  end.

Lemma reval_error_ext eenv1 env eenv2 e:
  (forall i, (i < max_error_var e)%nat ->
                 eenv1 i = eenv2 i) ->
  reval e env eenv1 = reval e env eenv2.
Proof.
  induction e; simpl.
  {
    destruct r; auto.
  }
  {
    intros.
    f_equal.
    auto.
  }
  intros.
  f_equal.
  {
    eapply IHe1; eauto with arith.
  }
  eapply IHe2; eauto with arith.
Qed.

Section WITHMAP.

Context {MSHIFT} {MAP: Map nat (type * rounding_knowledge') MSHIFT}.

Definition make_rounding
           (si: nat)
           (shift: MSHIFT)
           (kn:  rounding_knowledge') (ty: type) (x: rexpr):
  (rexpr * (nat * MSHIFT))
  :=
    match kn with
      | Unknown' =>
        let d := si in
        let es1 := mset shift d (ty, Normal') in
        let e := S d in
        let es2 := mset es1 e (ty, Denormal') in
        (
          RBinop Tree.Add
                 (RBinop Tree.Mul x
                         (RBinop Tree.Add (RAtom (RConst fone))
                                 (RAtom (RError d)))
                 )
                 (RAtom (RError e))
          , (S e, es2)
        )

      | Normal' =>
        let d := si in
        let es1 := mset shift d (ty, Normal') in
        (
          RBinop Tree.Mul x
                 (RBinop Tree.Add (RAtom (RConst fone))
                         (RAtom (RError d))
                 )
          , (S d, es1)
        )
      | Denormal' => 
        let e := si in
        let es1 := mset shift e (ty, Denormal') in
        (
          RBinop Tree.Add x
                 (RAtom (RError e))
          , (S e, es1)
        )
      | Denormal2' => 
        let e := si in
        let es1 := mset shift e (ty, Denormal2') in
        (
          RBinop Tree.Add x
                 (RAtom (RError e))
          , (S e, es1)
        )
    end.

Lemma make_rounding_shift_incr
      si
      shift
      kn ty x
      y si' shift':
  make_rounding si shift kn ty x = (y, (si', shift')) ->
  (si <= si')%nat
.
Proof.
  unfold make_rounding.
  destruct kn;
  inversion 1; subst; auto with arith.
Qed.

Lemma make_rounding_shift_unchanged
      si
      shift
      kn ty x
      y si' shift':
  make_rounding si shift kn ty x = (y, (si', shift')) ->
  forall i, (i < si)%nat ->
            mget shift' i = mget shift i.
Proof.
  unfold make_rounding.
  destruct kn.
  inversion 1; subst; intros.
  repeat rewrite (mget_set eq_nat_dec).
  destruct (Nat.eq_dec i (S si)); auto;
  destruct (Nat.eq_dec i si); auto;
  exfalso; lia.
all: try (    inversion 1; subst; intros;
    rewrite (mget_set eq_nat_dec);
    destruct (Nat.eq_dec i si); auto;
    exfalso; lia).
Qed.

Lemma make_rounding_shift_le
      si
      shift
      kn ty x
      y si' shift':
  make_rounding si shift kn ty x = (y, (si', shift')) ->
    (max_error_var x <= si)%nat ->
    (max_error_var y <= si')%nat.
Proof.
  unfold make_rounding.
  destruct kn;
  inversion 1; subst; simpl; intros;
  repeat (apply Max.max_lub; auto with arith).
Qed.

Definition error_bound ty k :=
  / 2 * Raux.bpow Zaux.radix2
  match k with
    | Unknown' => 0
    | Normal' => (- fprec ty + 1)
    | Denormal' =>  (3 - femax ty - fprec ty)
    | Denormal2' =>  (1 + (3 - femax ty - fprec ty))
  end.

Lemma error_bound_nonneg ty k:
  0 <= error_bound ty k.
Proof.
    unfold error_bound.
    apply Rmult_le_pos; try lra.
    apply Raux.bpow_ge_0.
Qed.

Definition error_bound' ty k :=
  match k with
    | Unknown' => /2
    | Normal' => / 2 * Raux.bpow Zaux.radix2 (- fprec ty + 1)
    | Denormal' => / 2 * Raux.bpow Zaux.radix2 (3 - femax ty - fprec ty) 
    | Denormal2' => Raux.bpow Zaux.radix2 (3 - femax ty - fprec ty) 
  end.

Lemma error_bound'_correct ty k:
  error_bound' ty k = error_bound ty k.
Proof.
  destruct k; try reflexivity;
  unfold error_bound', error_bound.
  simpl. lra.
  rewrite bpow_plus.
 rewrite <- Rmult_assoc.
 rewrite Rinv_l. lra.
 simpl. lra.
Qed.

Definition rounding_cond ty k x :=
  match k with
    | Unknown' => True
    | Normal' =>
      Raux.bpow Zaux.radix2 (3 - femax ty - 1) <= Rabs x
    | Denormal' =>
      Rabs x < Raux.bpow Zaux.radix2 (3 - femax ty)
    | Denormal2' => True
  end.

Lemma make_rounding_correct
      si shift kn ty x y si' shift':
  make_rounding si shift (round_knowl_denote kn) ty x = (y, (si', shift')) ->
  (max_error_var x <= si)%nat ->
  forall errors1,
    (forall i ty k,
       mget shift i = (ty, k) ->
       Rabs (errors1 i) <= error_bound ty k) ->
  forall env,
    rounding_cond ty (round_knowl_denote kn) (reval x env errors1) ->
  forall choice,
  exists errors2,
    (forall i,
       (i < si)%nat ->
       errors2 i = errors1 i)
    /\
    reval y env errors2 =
    Generic_fmt.round
      Zaux.radix2
      (FLT_exp (3 - femax ty - fprec ty) (fprec ty))
      (Generic_fmt.Znearest choice)
      (reval x env errors1)
    /\
    (forall i ty' k,
       mget shift' i = (ty', k) ->
       Rabs (errors2 i) <= error_bound ty' k)
.  

Proof. 
unfold make_rounding, rounding_cond.
intros.
destruct kn as [ [ | ] | ]; unfold round_knowl_denote in H2.
- (* Normal *)
  replace (3 - femax ty - 1)%Z with (3 - femax ty - fprec ty + fprec ty - 1)%Z in H2 by ring.
  generalize (Relative.relative_error_N_FLT_ex _ _ _ (fprec_gt_0 _) choice _ H2).
  destruct 1 as (eps & Heps & Hround).
  pose (errors2 i := if Nat.eq_dec i si  then eps else errors1 i).
  exists errors2.
  split; [ | split].
  * unfold errors2; intros; destruct (Nat.eq_dec i si); auto; lia.
  * inversion H; clear H; subst.
    simpl reval.
    rewrite Rmult_1_l.
    rewrite <- (reval_error_ext errors1).
   --
     unfold errors2.
     destruct (Nat.eq_dec si si); congruence.
   --  intros; unfold errors2; destruct (Nat.eq_dec i si); auto; exfalso; lia.
  * inversion H; clear H; subst.
    simpl reval.
    intros until i.
    rewrite (mget_set Nat.eq_dec).
    intros.
    unfold errors2.
    destruct (Nat.eq_dec i si); auto.
    inversion H; subst.
    assumption.
 - (* Denormal *)
  replace (3 - femax ty)%Z with (3 - femax ty - fprec ty + fprec ty)%Z in H2 by ring.
  generalize (Fprop_absolute.absolute_error_N_FLT _ _ (fprec_gt_0 _) _ choice _ H2).
  destruct 1 as (eps & Heps & Hround).
  pose (errors2 i := if Nat.eq_dec i si then eps else errors1 i).
  exists errors2.    
  split; [ | split].
  * unfold errors2; intros; destruct (Nat.eq_dec i si); auto; lia.
  * inversion H; clear H; subst. simpl reval.
    rewrite <- (reval_error_ext errors1).
   -- unfold errors2; destruct (Nat.eq_dec si si); congruence.
   -- intros; unfold errors2; destruct (Nat.eq_dec i si); auto; lia.
  * inversion H; clear H; subst. simpl reval.
     intros until i.
     rewrite (mget_set Nat.eq_dec).
     intros.
     unfold errors2.
     destruct (Nat.eq_dec i si); auto.
     inversion H; subst.
     auto.
-  (* None *)
 generalize (Relative.error_N_FLT Zaux.radix2 (3 - femax ty - fprec ty) (fprec ty) (fprec_gt_0 _)  choice (reval x env errors1)).
 destruct 1 as (eps & eta & Heps & Heta & _ & Hround).
 pose (errors2 i := if Nat.eq_dec i (S (si)) then eta
                          else if Nat.eq_dec i si then eps else  errors1 i).
 exists errors2.
 split; [ | split].
 + 
   unfold errors2.
   intros; destruct (Nat.eq_dec i (S si)); try lia; destruct (Nat.eq_dec i si); try lia; auto.
 + inversion H; clear H; subst.
    simpl reval.
    rewrite Rmult_1_l.     
  rewrite <- (reval_error_ext errors1).
  *
    unfold errors2.
    destruct (Nat.eq_dec si (S si)); try (exfalso; lia).
    destruct (Nat.eq_dec si si); try congruence.
    destruct (Nat.eq_dec (S si) (S si)); congruence.
  *
   intros.
   unfold errors2.
   destruct (Nat.eq_dec i (S si)); try lia.
   destruct (Nat.eq_dec i si); try lia.
   auto.
 +
   inversion H; clear H; subst.
    simpl reval.
  intros until i.
  repeat rewrite (mget_set Nat.eq_dec).
  intros.
  unfold errors2.
  destruct (Nat.eq_dec i (S si)).
  * inversion H; subst; assumption.
  * destruct (Nat.eq_dec i si); auto.
     inversion H; subst.
    assumption.
Qed.

Definition Rbinop_of_rounded_binop o :=
  match o with
    | PLUS => Tree.Add
    | MULT => Tree.Mul
    | MINUS => Tree.Sub
    | DIV => Tree.Div
  end.

Definition rnd_of_binop
           si
           (shift: MSHIFT)
           (ty: type)
           (o: binop) (r1 r2: rexpr)
  :=
    match o with
      | SterbenzMinus => (RBinop Tree.Sub r1 r2, (si, shift))
      | PlusZero minus zero_left =>
        ((
            if zero_left
            then
              if minus
              then RUnop Tree.Neg r2
              else r2
            else
              r1
          ), (si, shift))       
      | Rounded2 o' k => 
        make_rounding si shift (round_knowl_denote k) ty                      
                      (RBinop (Rbinop_of_rounded_binop o') r1 r2)
    end.

Definition rnd_of_cast
           si
           (shift: MSHIFT)
           (tyfrom tyto: type)
           (k: rounding_knowledge')
           (r: rexpr) :=
  if type_leb tyfrom tyto
  then
    (r, (si, shift))
  else
    make_rounding si shift k tyto r
.

Definition Runop_of_rounded_unop ty o :=
  match o with
    | SQRT => RUnop Tree.Sqrt
    | InvShift n _ => RBinop Tree.Mul (RAtom (RConst (B2F (B2 ty (- Z.pos n)))))
  end.

Definition Runop_of_exact_unop ty o :=
  match o with
    | Abs => RUnop Tree.Abs
    | Opp => RUnop Tree.Neg
    | Shift n _ => RBinop Tree.Mul (RAtom (RConst (B2F (B2 ty (Z.of_N n)))))
  end.

Definition rnd_of_unop
           si
           (shift: MSHIFT)
           (ty: type)
           (o: unop) (r: rexpr)
  :=
    match o with
      | Rounded1 (InvShift n ltr) (Some Normal) =>
                  (Runop_of_rounded_unop ty (InvShift n ltr) r, (si, shift))
      | Rounded1 (InvShift n _) _ =>
           make_rounding si shift Denormal2' ty
              ((RBinop Tree.Mul (RAtom (RConst (B2F (B2 ty (- Z.pos n)))))) r)
      | Rounded1 o k =>
        make_rounding si shift (round_knowl_denote k) ty
                      (Runop_of_rounded_unop ty o r)
      | Exact1 o => (Runop_of_exact_unop ty o r, (si, shift))
      | CastTo ty' k => rnd_of_cast si shift ty ty' (round_knowl_denote k) r
    end.

Fixpoint rndval 
         si
         (shift: MSHIFT)
         (e: expr) {struct e}
 :=
  match e with
    | Const ty f => (RAtom (RConst (B2F f)), (si, shift))
    | Var ty i => (RAtom (RVar ty i), (si, shift))
    | Binop b e1 e2 =>
      let '(r1, (si1, s1)) := rndval si shift e1 in
      let '(r2, (si2, s2)) := rndval si1 s1 e2 in
      rnd_of_binop si2 s2 (type_of_expr e) b r1 r2
    | Unop b e1 =>
      let '(r1, (si1, s1)) := rndval si shift e1 in
      rnd_of_unop si1 s1 (type_of_expr e1) b r1
  end.

Lemma rnd_of_binop_shift_incr si shift ty b r1 r2 r si' shift':
  rnd_of_binop si shift ty b r1 r2 = (r, (si', shift')) ->
  (si <= si')%nat.
Proof.
  destruct b; simpl; intros.
  {
    eapply make_rounding_shift_incr; eauto.
  }
  {
    inversion H; clear H; subst.
    auto with arith.
  }
  {
    inversion H; clear H; subst.
    auto with arith.
  }
Qed.

Lemma rnd_of_binop_shift_le si shift ty b r1 r2 r si' shift':
  rnd_of_binop si shift ty b r1 r2 = (r, (si', shift')) ->
    (max_error_var r1 <= si)%nat ->
    (max_error_var r2 <= si)%nat ->
    (max_error_var r <=  si')%nat.
Proof.
  destruct b; simpl; intros.
  {
    eapply make_rounding_shift_le; eauto.
    simpl.
    apply Nat.max_lub; auto.
  }
  {
    inversion H; clear H; subst.
    simpl.
    apply Nat.max_lub; auto.
  }
  {
    inversion H; clear H; subst.
    destruct zero_left; auto.
    destruct minus; auto.
  }
Qed.

Lemma rnd_of_binop_shift_unchanged  si shift ty b r1 r2 r si' shift':
  rnd_of_binop si shift ty b r1 r2 = (r, (si', shift')) ->
  forall i, (i < si)%nat ->
            mget shift' i = mget shift i.
Proof.
  destruct b; simpl; intros.
  {
    eapply make_rounding_shift_unchanged; eauto.
  }
  {
    congruence.
  }
  {
    congruence.
  }
Qed.

Lemma rnd_of_cast_shift_incr si shift ty ty0 knowl r1 y si' shift':
  rnd_of_cast si shift ty ty0 knowl r1 = (y, (si', shift')) ->
  (si <= si')%nat.
Proof.
  unfold rnd_of_cast.
  destruct (
      type_leb ty ty0
    ).
  {
    inversion_clear 1; auto with arith.
  }
  intros.
  eapply make_rounding_shift_incr; eauto.
Qed.

Lemma rnd_of_cast_shift_le si shift ty ty0 knowl r1 y si' shift':
  rnd_of_cast si shift ty ty0 knowl r1 = (y, (si', shift')) ->
  (max_error_var r1 <= si)%nat ->
    (max_error_var y <= si')%nat.
Proof.
  unfold rnd_of_cast.
  destruct (
      type_leb ty ty0
    ).
  {
    congruence.
  }
  intros; eapply make_rounding_shift_le; eauto.
Qed.

Lemma rnd_of_cast_shift_unchanged si shift ty ty0 knowl r1 y si' shift':
  rnd_of_cast si shift ty ty0 knowl r1 = (y, (si', shift')) ->
  forall i, (i < si)%nat ->
            mget shift' i = mget shift i.
Proof.
  unfold rnd_of_cast.
  destruct (type_leb ty ty0).
  {
    congruence.
  }
  apply make_rounding_shift_unchanged.
Qed.
    
Lemma rnd_of_unop_shift_incr si shift ty u r1 y si' shift':
  rnd_of_unop si shift ty u r1 = (y, (si', shift')) ->
  (si <= si')%nat.
Proof.
  destruct u; simpl.
- (* Rounded1 *)
  destruct op.
 +
     apply make_rounding_shift_incr.
 + destruct knowl as [ [ | ] | ].
  * (* Some Normal *)
   inversion_clear 1; auto with arith.
  *  apply (make_rounding_shift_incr _ _ Denormal2').
  *  apply (make_rounding_shift_incr _ _ Denormal2').
- (* Exact1 *)
   inversion_clear 1; auto with arith.
- (* CastTo *)
  apply rnd_of_cast_shift_incr.
Qed.

Lemma rnd_of_unop_shift_le si  shift ty u r1 y si' shift':
  rnd_of_unop si shift ty u r1 = (y, (si', shift')) ->
  (max_error_var r1 <= si)%nat ->
  (max_error_var y  <=  si')%nat.
Proof.
  destruct u; simpl; intros.
- (* Rounded1 *)
 destruct op.
 + eapply make_rounding_shift_le; eauto.
 + destruct knowl as [ [ | ] | ].
  * (* Some Normal *)
    inversion H; clear H; subst; simpl. auto.
  * eapply (make_rounding_shift_le _ _ Denormal2'); eauto.
  * eapply (make_rounding_shift_le _ _ Denormal2'); eauto.
- (* Exact1 *)
    inversion H; clear H; subst; simpl.
    destruct o; simpl; auto.
- (* CastTo *)
  eapply rnd_of_cast_shift_le; eauto.
Qed.

Lemma rnd_of_unop_shift_unchanged si  shift ty u r1 y si' shift':
  rnd_of_unop si shift ty u r1 = (y, (si', shift')) ->
  forall i, (i < si)%nat ->
            mget shift' i = mget shift i.
Proof.
  destruct u; simpl.
- (* Rounded1 *)
  destruct op.
 + apply make_rounding_shift_unchanged.
 + destruct knowl as [ [ | ] | ].
  * (* Some Normal *)
        inversion_clear 1; auto with arith.
  * apply (make_rounding_shift_unchanged _ _ Denormal2').
  * apply (make_rounding_shift_unchanged _ _ Denormal2').
- (* Exact1 *)
    inversion_clear 1; auto with arith.
- (* CastTo *)
  apply rnd_of_cast_shift_unchanged.
Qed.

Lemma rndval_shift_incr x:
  forall si shift y si' shift',
    rndval si shift x = (y, (si', shift')) ->
    (si <= si')%nat.
Proof.
  induction x; simpl.
- (* Const *)
    inversion_clear 1; intros; auto with arith.
- (* Var *)
    inversion_clear 1; intros; auto with arith.
- (* Binop *)
    intros.
    destruct (rndval si shift x1) as (r1 & si1 & s1) eqn:EQ1.
    destruct (rndval si1 s1 x2) as (r2 & si2 & s2) eqn:EQ2.
    eapply le_trans.
    {
      eapply IHx1; eauto.
    }
    eapply le_trans.
    {
      eapply IHx2; eauto.
    }
    eapply rnd_of_binop_shift_incr; eauto.
- (* Unop *)
  intros.
  destruct (rndval si shift x) as (r1 & si1 & s1) eqn:EQ1.
  eapply le_trans.
  {
    eapply IHx; eauto.
  }
  eapply rnd_of_unop_shift_incr; eauto.
Qed.

Lemma rndval_shift_le x:
  forall si shift y si' shift',
    rndval si shift x = (y, (si', shift')) ->
    (max_error_var y <=  si')%nat.
Proof.
  induction x; simpl.
- (* Const *)
    inversion_clear 1; simpl; auto with arith.
- (* Var *)
    inversion_clear 1; simpl; auto with arith.
- (* Binop *)
    intros.
    destruct (rndval si shift x1) as (r1 & si1 & s1) eqn:EQ1.
    destruct (rndval si1 s1 x2) as (r2 & si2 & s2) eqn:EQ2.
    eapply rnd_of_binop_shift_le; eauto.
    eapply le_trans.
    {
      eapply IHx1; eauto.
    }
    eapply rndval_shift_incr; eauto.
- (* Unop *)
  intros.
  destruct (rndval si shift x) as (r1 & si1 & s1) eqn:EQ1.
  eapply rnd_of_unop_shift_le; eauto.
Qed.

Lemma rndval_shift_unchanged x:
  forall si shift y si' shift',
    rndval si shift x = (y, (si', shift')) ->
  forall i, (i < si)%nat ->
            mget shift' i = mget shift i.
Proof.
  induction x; simpl.
- (* Const *)
    inversion_clear 1; intros; auto with arith.
- (* Var *)
    inversion_clear 1; intros; auto with arith.
- (* Binop *)
    intros.
    destruct (rndval si shift x1) as (r1 & si1 & s1) eqn:EQ1.
    destruct (rndval si1 s1 x2) as (r2 & si2 & s2) eqn:EQ2.
    etransitivity.
    {
      eapply rnd_of_binop_shift_unchanged; eauto.
      eapply lt_le_trans; [ eassumption | ].
      etransitivity.
      {
        eapply rndval_shift_incr; eauto.
      }
      eapply rndval_shift_incr; eauto.
    }
    etransitivity.
    {
      eapply IHx2; eauto.
      eapply lt_le_trans; [ eassumption | ].
      eapply rndval_shift_incr; eauto.
    }
    eapply IHx1; eauto.
- (* Unop *)
  intros.
  destruct (rndval si shift x) as (r1 & si1 & s1) eqn:EQ1.
  etransitivity.
  {
    eapply rnd_of_unop_shift_unchanged; eauto.
    eapply lt_le_trans; [ eassumption | ].
    eapply rndval_shift_incr; eauto.
  }
  eapply IHx; eauto.
Qed.

(*  "(a, b) holds" iff 0 (if b then < else <=) a *)
Definition cond: Type := (rexpr * bool).

Definition False_cond : cond  := 
   (* a condition that is impossible to satisfy *)
 (RAtom (RConst (Float radix2 0 0)), true).

Definition eval_cond1 env m (c: cond) :=
  let '(e, b) := c in
  forall errors,
    (forall i ty' k,
       mget m i = (ty', k) ->
       Rabs (errors i) <= error_bound ty' k) ->
    (if b then Rlt else Rle) 0 (reval e env errors)
.

Lemma evalcond1_False: forall env m, eval_cond1 env m False_cond -> False.
Proof.
intros.
hnf in H.
specialize (H (fun _ => 0)).
match type of H with ?A -> _ => assert A end;
  [ |  apply H in H0; simpl in H0; lra].
intros. unfold error_bound. destruct k.
- 
simpl.
rewrite Rabs_R0.
lra.
-
pose proof (bpow_gt_0 radix2 (Z.pos_sub 1 (fprecp ty'))).
set (j := bpow _ _) in *. clearbody j.
rewrite Rabs_pos_eq by lra.
lra.
-
pose proof (bpow_gt_0 radix2 (3 - femax ty' - fprec ty')).
set (j := bpow _ _) in *. clearbody j.
rewrite Rabs_pos_eq by lra.
lra.
-
rewrite Rabs_R0.
apply Rmult_le_pos.
lra.
apply Rlt_le. apply bpow_gt_0.
Qed.

Lemma eval_cond1_preserved m1 m2 env c:
  ( forall e b,
      c = (e, b) ->
      forall i,
        (i < max_error_var e)%nat ->
        mget m2 i = mget m1 i
  ) ->
  eval_cond1 env m1 c ->
  eval_cond1 env m2 c.
Proof.
  unfold eval_cond1.
  intros.
  destruct c.
  intros.
  rewrite <- (reval_error_ext (fun i =>
                              if Nat.ltb i (max_error_var r)
                              then errors i
                              else 0)).
  {
    apply H0.
    intros.
    destruct (Nat.ltb i (max_error_var r)) eqn:LTB.
    {
      apply H1.
      erewrite H; eauto.
      apply Nat.ltb_lt.
      assumption.
    }
    rewrite Rabs_R0.
    apply error_bound_nonneg.
  }
  intros.
  rewrite <- Nat.ltb_lt in H2.
  rewrite H2.
  reflexivity.
Qed.

Fixpoint revars (r: rexpr): MSET.t :=
  match r with
    | RAtom (RError n) => MSET.singleton n
    | RUnop _ e => revars e
    | RBinop _ e1 e2 => MSET.union (revars e1) (revars e2)
    | _ => MSET.empty
  end.

Lemma reval_error_ext_strong errors1 env errors2 e:
  (forall i, MSET.In i (revars e) -> errors2 i = errors1 i) ->
  reval e env errors2 = reval e env errors1.
Proof.
  induction e; simpl.
  {
    destruct r; auto.
    intros.
    apply H.
    apply MSET.singleton_spec.
    reflexivity.
  }
  {
    intros.
    intuition congruence.
  }
  intros.
  rewrite IHe1.
  {
    rewrite IHe2.
    {
      reflexivity.
    }
    intros.
    apply H.
    rewrite MSET.union_spec.
    tauto.
  }
  intros.
  apply H.
  rewrite MSET.union_spec.
  tauto.
Qed.

Lemma revars_max_error_var e:
  forall i, MSET.In i (revars e) -> 
            (i < max_error_var e)%nat.
Proof.
  induction e; simpl; auto; intro.
  {
    destruct r; generalize (@MSET.empty_spec i); try contradiction.
    intros _.
    rewrite MSET.singleton_spec.
    intro; subst; auto with arith.
  }
  rewrite MSET.union_spec.
  destruct 1.
  {
    eapply lt_le_trans.
    { eapply IHe1; eauto. }
    apply Nat.le_max_l.
  }
  eapply lt_le_trans.
  { eapply IHe2; eauto. }
  apply Nat.le_max_r.
Qed.

Context {MSHIFT'} {MAP': Map nat R MSHIFT'}.

Export List.

Fixpoint enum_forall' t_ (Q: nat -> _ -> Prop) (l: list nat) (P: MSHIFT' -> Prop): Prop :=
  match l with
    | nil => P (mempty t_)
    | a :: q =>
      enum_forall' t_ Q q (fun errors =>
                            forall u,
                              Q a u ->
                              P (mset errors a u))
  end.

Lemma enum_forall_correct'  t_ (Q: _ -> _ -> Prop) (Ht_: forall i, Q i t_) l:
  forall (P: _ -> Prop),
    (forall errors1 errors2,
       (forall i, In i l -> mget errors2 i = mget errors1 i) ->
       P errors1 -> P errors2) ->
    (forall errors,
       (forall i, Q i (mget errors i)) ->
       P errors) <->
    enum_forall' t_ Q l P.
Proof.
  induction l; simpl; intros.
  {
    split.
    {
      intros.
      eapply H0.
      intros.
      rewrite mget_empty.
      auto.
    }
    intros.
    eapply H; [ | eassumption ].
    contradiction.
  }
  specialize (IHl (fun errors => forall u, Q a u -> P (mset errors a u))).
  destruct IHl.
  {
    simpl.
    intros.
    eapply H.
    2: eapply H1; eauto.
    intros.
    repeat rewrite (mget_set Nat.eq_dec).
    destruct (Nat.eq_dec i a); auto.
    destruct H3; try congruence.
    auto.
  }
  split; intros.
  {
    apply H0; intros.
    apply H2.
    intros.
    repeat rewrite (mget_set Nat.eq_dec).
    destruct (Nat.eq_dec i a); auto.
    congruence.
  }
  eapply H.
  2: eapply H1 with (u := mget errors a); eauto.
  intros.
  repeat rewrite (mget_set Nat.eq_dec).
  destruct (Nat.eq_dec i a); auto.
Qed.

Definition enum_forall t_ Q l P :=
    enum_forall' t_ Q l (fun m => P (mget m)).  

Theorem enum_forall_correct  t_ (Q: _ -> _ -> Prop) (Ht_: forall i, Q i t_) l:
  forall (P: _ -> Prop),
    (forall errors1 errors2,
       (forall i, In i l -> errors2 i = errors1 i) ->
       P errors1 -> P errors2) ->
    (forall errors,
       (forall i, Q i (mget errors i)) ->
       P (mget errors)) <->
    enum_forall t_ Q l P.
Proof.
  unfold enum_forall.
  intros.
  rewrite <- (enum_forall_correct' t_ Q Ht_ l (fun m => P (mget m))); try tauto.
  intros.
  eapply H; eauto.
Qed.

Section EVAL_COND2.

Let P env e (b: bool) errors :=
  (if b then Rlt else Rle) 0 (reval e env errors).

Let Q m i err := 
  let '(ty', k) := mget m i in
  Rabs err <= error_bound ty' k
.

Definition eval_cond2 env m (c: cond) :=
  let '(e, b) := c in
  enum_forall 0 (Q m) (MSET.elements (revars e)) (P env e b)
.

Lemma eval_cond2_correct env m c:
  eval_cond2 env m c <-> eval_cond1 env m c.
Proof.
  unfold eval_cond2, eval_cond1.
  destruct c.
  rewrite <- enum_forall_correct.
  {
    unfold Q, P.
    split; intros.
    {
      destruct (finite_errors_ex 0 (max_error_var r) errors).
      rewrite <- (reval_error_ext (mget x)).
      {
        eapply H; eauto.
        intros.
        destruct (mget m i) eqn:?.
        rewrite H1.
        destruct (Nat.ltb i (max_error_var r)); auto.
        rewrite Rabs_R0.
        apply error_bound_nonneg.
      }
      intros.
      rewrite H1.
      rewrite <- Nat.ltb_lt in H2.
      rewrite H2.
      reflexivity.
    }
    apply H.
    intros.
    specialize (H0 i).
    rewrite H1 in H0.
    assumption.
  }
  {
    unfold Q.
    intros.
    destruct (mget m i).
    rewrite Rabs_R0.
    apply error_bound_nonneg.
  }
  unfold P.
  intros.
  rewrite (reval_error_ext_strong errors1); auto.
  intros.
  apply H.
  rewrite <- MSET.elements_spec1 in H1.
  rewrite SetoidList.InA_alt in H1.
  destruct H1.
  intuition congruence.
Qed.

End EVAL_COND2.

Definition is_div o :=
  match o with
    | DIV => true
    | _ => false
  end.

Definition rounding_cond_ast ty k x: list cond :=
  match k with
    | Normal' =>
      (RBinop Tree.Sub (RUnop Tree.Abs x) (RAtom (RConst (Defs.Float _ 1 (3 - femax ty - 1)))), false) :: nil
    | Denormal' =>
      (RBinop Tree.Sub (RAtom (RConst (Defs.Float _ 1 (3 - femax ty)))) (RUnop Tree.Abs x), true) :: nil
    | Denormal2' => nil
    | Unknown' => nil 
  end.

Lemma rounding_cond_ast_shift ty k x e b:
  In (e, b) (rounding_cond_ast ty k x) ->
  (max_error_var e <= max_error_var x)%nat.
Proof.
  Opaque Zminus.
  destruct k; simpl; try tauto;
    intro K;
    inversion K; try contradiction;
    clear K;
    subst;
    inversion H; clear H; subst;
    simpl;
    try rewrite Max.max_0_r;
    auto with arith.
  Transparent Zminus.
Qed.

Lemma rounding_cond_ast_correct m env ty knowl r errors:
  (forall i ty k,
     mget m i = (ty, k) ->
     Rabs (errors i) <= error_bound ty k) ->
  (forall i, In i (rounding_cond_ast ty knowl r) -> eval_cond1 env m i) ->
  rounding_cond ty knowl (reval r env errors)
.
Proof.
  intros.
  unfold rounding_cond.
  destruct knowl; auto.
 -
  cbn -[Zminus] in * |- *  .
    specialize (H0 _ (or_introl _ (refl_equal _))).
    cbn -[Zminus] in *.
    specialize (H0 _ H).
    lra.
 -
  specialize (H0 _ (or_introl _ (refl_equal _))).
  cbn -[Zminus] in *.
  specialize (H0 _ H).
  lra.
Qed.

Definition no_overflow ty x: cond := 
  (RBinop Tree.Sub (RAtom (RConst (Defs.Float _ 1 (femax ty)))) (RUnop Tree.Abs x), true).

Definition rnd_of_plus_zero_cond (zero_left: bool) r1 r2 :=
  (RUnop Tree.Neg (RUnop Tree.Abs (if zero_left then r1 else r2)), false) :: nil.  

Definition rnd_of_binop_with_cond
           si
           (shift: MSHIFT)
           (ty: type)
           (o: binop) (r1 r2: rexpr):
  ((rexpr * (nat * MSHIFT)) * list cond)
  :=
    match o with
      | SterbenzMinus =>
        ((RBinop Tree.Sub r1 r2, (si, shift)),
         (RBinop Tree.Sub r1 (RBinop Tree.Mul r2 (RAtom (RConst (Defs.Float _ 1 (-1))))), false)
           ::
           (RBinop Tree.Sub (RBinop Tree.Mul r2 (RAtom (RConst (Defs.Float _ 1 1)))) r1, false)
           :: nil)
      | PlusZero minus zero_left =>
        (
          ((
              if zero_left
              then
                if minus
                then RUnop Tree.Neg r2
                else r2
              else
                r1
            ), (si, shift))
          ,
          rnd_of_plus_zero_cond zero_left r1 r2
        )
      | Rounded2 o' k =>
        let ru := RBinop (Rbinop_of_rounded_binop o') r1 r2 in
        let rs := make_rounding si shift (round_knowl_denote k) ty ru in
        let '(r, _) := rs in
        (rs,
         (if is_div o' then (RUnop Tree.Abs r2, true) :: nil else nil)
           ++ no_overflow ty r :: rounding_cond_ast ty (round_knowl_denote k) ru)
    end.

Lemma rounding_cond_ast_shift_cond ty k r e b:
  In (e, b) (rounding_cond_ast ty k r) ->
     (max_error_var e = max_error_var r)%nat.
Proof.
  unfold rounding_cond_ast.
  destruct k; try contradiction.
-
    destruct 1; try contradiction.
    Opaque Zminus. inversion H; clear H; subst. Transparent Zminus.
    simpl.
    apply Max.max_0_r.
-
  destruct 1; try contradiction.
  Opaque Zminus. inversion H; clear H; subst. Transparent Zminus.
  reflexivity.
Qed.

Lemma rnd_of_binop_with_cond_shift_cond si shift ty o r1 r2 r' si' shift' cond:
  rnd_of_binop_with_cond si shift ty o r1 r2 = ((r', (si', shift')), cond) ->
  (max_error_var r1 <= si)%nat ->
  (max_error_var r2 <= si)%nat ->
  forall e b,
    In (e, b) cond ->
    (max_error_var e <= si')%nat.
Proof.
  destruct o; simpl.
  {
    destruct (
        make_rounding si shift (round_knowl_denote knowl) ty
                      (RBinop (Rbinop_of_rounded_binop op) r1 r2)
    ) eqn:EQ.
    intro K.
    inversion K; clear K; subst.
    intros.
    apply in_app_or in H1.
    destruct H1.
    {
      destruct (is_div op); try contradiction.
      destruct H1; try contradiction.
      inversion H1; clear H1; subst.
      simpl.
      apply make_rounding_shift_incr in EQ.
      lia.
    }
    destruct H1.
    {
      inversion H1; clear H1; subst.
      simpl.
      eapply make_rounding_shift_le; eauto.
      simpl.
      apply Max.max_lub; auto.
    }
    apply rounding_cond_ast_shift_cond in H1.
    rewrite H1.
    simpl.
    apply make_rounding_shift_incr in EQ.
    apply Max.max_lub; lia.
  }
  {
    intro K.
    inversion K; clear K; subst.
    simpl.
    destruct 3.
    {
      inversion H1; clear H1; subst.
      simpl.
      rewrite Max.max_0_r.
      apply Max.max_lub; lia.
    }
    destruct H1; try contradiction.
    inversion H1; clear H1; subst.
    simpl.
    rewrite Max.max_0_r.
    apply Max.max_lub; lia.
  }
  {
    intro K.
    inversion K; clear K; subst.
    simpl.
    destruct 3; try contradiction.
    inversion H1; clear H1; subst.
    simpl.
    destruct zero_left; auto.
  }
Qed.

Definition rnd_of_cast_with_cond
           si
           (shift: MSHIFT)
           (tyfrom tyto: type)
           (k: rounding_knowledge')
           (r: rexpr) :=
  if type_leb tyfrom tyto
  then
    ((r, (si, shift)), nil)
  else
    let rs := make_rounding si shift k tyto r in
    let '(r', _) := rs in
    (rs, no_overflow tyto r' :: rounding_cond_ast tyto k r)
.

Lemma rnd_of_cast_with_cond_shift_cond
      si shift tyfrom tyto k r r' si' shift' cond:
  rnd_of_cast_with_cond si shift tyfrom tyto k r = ((r', (si', shift')), cond) ->
  (max_error_var r <= si)%nat ->
  forall e b,
    In (e, b) cond ->
    (max_error_var e <= si')%nat.
Proof.
  unfold rnd_of_cast_with_cond.
  destruct (type_leb tyfrom tyto).
  {
    intros.
    inversion H; clear H; subst.
    contradiction.
  }
  destruct (make_rounding si shift k tyto r) eqn:EQ.
  destruct p.
  intro K.
  inversion K; clear K; subst.
  destruct 2.
  {
    inversion H0; clear H0; subst.
    simpl.
    eapply make_rounding_shift_le; eauto.
  }
  apply rounding_cond_ast_shift_cond in H0.
  rewrite H0.
  apply make_rounding_shift_incr in EQ.
  lia.
Qed.

Definition rnd_of_unop_with_cond
           si
           (shift: MSHIFT)
           (ty: type)
           (o: unop) (r1: rexpr)
  :=
    match o with
      | Rounded1 (InvShift n ltr) (Some Normal) =>
        let ru := Runop_of_rounded_unop ty  (InvShift n ltr) r1 in
        ((ru, (si, shift)), 
            (RBinop Tree.Sub (RUnop Tree.Abs r1) (RAtom (RConst (Defs.Float _ 1 (3 - femax ty + Z.pos n - 1)))), false) :: nil)
      | Rounded1 (InvShift n _) _ =>
        let ru := RBinop Tree.Mul (RAtom (RConst (B2F (B2 ty (- Z.pos n))))) r1 in
        let rs := make_rounding si shift Denormal2' ty ru in
        let '(r, _) := rs in
        (rs, nil)
      | Rounded1 op k =>
        let ru := Runop_of_rounded_unop ty op r1 in
        let rs := make_rounding si shift (round_knowl_denote k) ty ru in
        let '(r, _) := rs in
        (rs, (r1, false) :: rounding_cond_ast ty (round_knowl_denote k) ru)
      | Exact1 o => 
        let ru := Runop_of_exact_unop ty o r1 in
        ((ru, (si, shift)), 
         match o with
           | Shift _ _ => no_overflow ty ru :: nil
           | _ => nil
         end)
      | CastTo ty' k => rnd_of_cast_with_cond si shift ty ty' (round_knowl_denote k) r1
    end.

Lemma rnd_of_unop_with_cond_shift_cond si shift ty o r1 r' si' shift' cond:
  rnd_of_unop_with_cond si shift ty o r1 = ((r', (si', shift')), cond) ->
  (max_error_var r1 <= si)%nat ->
  forall e b,
    In (e, b) cond ->
    (max_error_var e <= si')%nat.
Proof.
  destruct o; cbn -[Zminus].
- (* Rounded1 *)
 destruct op.
 + (* SQRT *)
    destruct (
        make_rounding si shift (round_knowl_denote knowl) ty (Runop_of_rounded_unop ty SQRT r1)
      ) as [r'1 [si'1 shift'1]] eqn:EQ.
    intro K.
    inversion K; clear K; subst.
    intros.
    destruct H0.
    {
      inversion H0; clear H0; subst.
      eapply make_rounding_shift_incr in EQ.
      lia.
    }
    apply rounding_cond_ast_shift_cond in H0.
    rewrite H0.
    simpl.
    apply make_rounding_shift_incr in EQ.
    lia.
 + (* InvShift *)
    destruct knowl as [ [ | ] | ].
  * (* Some Normal *)
    intro K.
    inversion K; clear K; subst.
    intros.
    destruct H0; try contradiction.
    inversion H0; clear H0; subst.
    simpl.
    rewrite Max.max_0_r.
    assumption.
  * intros. inversion H; clear H; subst. inversion H1.
  * intros. inversion H; clear H; subst. inversion H1.
- (* Exact1 *)
    intro K.
    inversion K; clear K; subst.
    intros.
    destruct o; try contradiction.
   + (* Shift *)
      destruct H0; try contradiction.
      inversion H0; clear H0; subst.
      simpl.
      assumption.
- (* CastTo *)
  apply rnd_of_cast_with_cond_shift_cond.
Qed.

Fixpoint rndval_with_cond'
         si
         (shift: MSHIFT)
         (e: expr) {struct e}
  :=
  match e with
    | Const ty f => ((RAtom (RConst (B2F f)), (si, shift)), nil)
    | Var ty i => ((RAtom (RVar ty i), (si, shift)), nil)
    | Binop b e1 e2 =>
      let '((r1, (si1, s1)), p1) := rndval_with_cond' si shift e1 in
      let '((r2, (si2, s2)), p2) := rndval_with_cond' si1 s1 e2 in
      let ty := type_of_expr e in
      let '(rs, p) := rnd_of_binop_with_cond si2 s2 ty b r1 r2 in
      (rs, p ++ (p1 ++ p2))
    | Unop b e1 =>
      let '((r1, (si1, s1)), p1) := rndval_with_cond' si shift e1 in
      let '(rs, p) := rnd_of_unop_with_cond si1 s1 (type_of_expr e1) b r1 in
      (rs, p ++ p1)
  end. 

Lemma rnd_of_binop_with_cond_left si shift ty o r1 r2:
  fst (rnd_of_binop_with_cond si shift ty o r1 r2) =
  rnd_of_binop si shift ty o r1 r2.
Proof.
  unfold rnd_of_binop_with_cond, rnd_of_binop.
  destruct o; simpl; auto.
  destruct (
make_rounding si shift (round_knowl_denote knowl) ty
         (RBinop (Rbinop_of_rounded_binop op) r1 r2)
    ); simpl; auto.
Qed.

Lemma rnd_of_cast_with_cond_left si shift ty ty0 knowl r1:
   fst (rnd_of_cast_with_cond si shift ty ty0 knowl r1) =
   rnd_of_cast si shift ty ty0 knowl r1.
Proof.
  unfold rnd_of_cast_with_cond, rnd_of_cast.
  destruct (
      type_leb ty ty0
    ); auto.
  destruct (make_rounding si shift knowl ty0 r1).
  auto.
Qed.

Lemma rnd_of_unop_with_cond_left si shift ty o r1:
  fst (rnd_of_unop_with_cond si shift ty o r1) =
  rnd_of_unop si shift ty o r1.
Proof.
  unfold rnd_of_unop_with_cond, rnd_of_unop.
  destruct o; simpl; auto.
- (* Rounded1 *)
 destruct op.
 + (* SQRT *)
    destruct (
        make_rounding si shift (round_knowl_denote knowl) ty
                      (Runop_of_rounded_unop ty SQRT r1)
      ); simpl; auto.
 + (* InvShift *)
    destruct knowl as [ [ | ] | ]; simpl; auto.
- (* CastTo *)
  apply rnd_of_cast_with_cond_left.
Qed.

Lemma rndval_with_cond_left e:
  forall si shift,
    fst (rndval_with_cond' si shift e) = rndval si shift e.
Proof.
  induction e; simpl; auto.
- (* Binop *)
    intros.
    specialize (IHe1 si shift).
    destruct (rndval_with_cond' si shift e1).
    simpl in IHe1.
    subst.
    destruct (rndval si shift e1).
    destruct p.
    specialize (IHe2 n m).
    destruct (rndval_with_cond' n m e2).
    simpl in IHe2.
    subst.
    destruct (rndval n m e2).
    destruct p.
    specialize (rnd_of_binop_with_cond_left n0 m0 (type_lub (type_of_expr e1) (type_of_expr e2)) b r r0).
    destruct (rnd_of_binop_with_cond n0 m0 (type_lub (type_of_expr e1) (type_of_expr e2)) b r r0);
      simpl; auto.
- (* Unop *)
   intros.
  specialize (IHe si shift).
  destruct (rndval_with_cond' si shift e); simpl in *; subst.
  destruct (rndval si shift e).
  destruct p.
  specialize (rnd_of_unop_with_cond_left n m (type_of_expr e) u r).
  destruct (
      rnd_of_unop_with_cond n m (type_of_expr e) u r
    ); simpl; auto. 
Qed.

Lemma rndval_with_cond_shift_cond e:
  forall si shift r' si' shift' cond,
  rndval_with_cond' si shift e = ((r', (si', shift')), cond) ->
  forall e' b',
    In (e', b') cond ->
    (max_error_var e' <= si')%nat.
Proof.
  induction e; simpl; intros.
  {
    inversion H; clear H; subst; contradiction.
  }
  {
    inversion H; clear H; subst; contradiction.
  }
  {
    destruct (rndval_with_cond' si shift e1) as [[r1 [si1 s1]] p1] eqn:EQ1.
    destruct (rndval_with_cond' si1 s1 e2) as [[r2 [si2 s2]] p2] eqn:EQ2.
    destruct (rnd_of_binop_with_cond si2 s2 (type_lub (type_of_expr e1) (type_of_expr e2)) b r1 r2)
             as [rs' p']
             eqn:EQ.
    inversion H; clear H; subst.
    generalize (rndval_with_cond_left e1 si shift).
    rewrite EQ1.
    simpl.
    intros.
    symmetry in H.   
    generalize (rndval_with_cond_left e2 si1 s1).
    rewrite EQ2.
    simpl.
    intros.
    symmetry in H1.
    generalize (rnd_of_binop_with_cond_left si2 s2 (type_lub (type_of_expr e1) (type_of_expr e2)) b r1 r2).
    rewrite EQ.
    intros.
    symmetry in H2.
    simpl in H2.
    generalize H.
    intro.
    apply rndval_shift_incr in H.
    apply rndval_shift_le in H3.
    generalize H1.
    intro.
    apply rndval_shift_incr in H1.
    apply rndval_shift_le in H4.
    generalize H2.
    intro.
    apply rnd_of_binop_shift_incr in H2.
    apply rnd_of_binop_shift_le in H5; try lia.
    apply in_app_or in H0.
    destruct H0.
    {
      eapply rnd_of_binop_with_cond_shift_cond; eauto.
      lia.
    }
    apply in_app_or in H0.
    destruct H0.
    {
      eapply IHe1 in H0; [ | eassumption ] .
      lia.
    }
    eapply IHe2 in H0; [ | eassumption ].
    lia.
  }
  destruct (rndval_with_cond' si shift e) as [[r1 [si1 s1]] p1] eqn:EQ1.
  destruct (rnd_of_unop_with_cond si1 s1 (type_of_expr e) u r1) eqn:EQ.
  inversion H; clear H; subst.
  generalize (rndval_with_cond_left e si shift).
  rewrite EQ1.
  simpl.
  intros.
  symmetry in H.   
  generalize (rnd_of_unop_with_cond_left si1 s1 (type_of_expr e) u r1).
  rewrite EQ.
  intros.
  symmetry in H1.
  simpl in H1.
  generalize H.
  intro.
  apply rndval_shift_incr in H.
  apply rndval_shift_le in H2.
  generalize H1.
  intro.
  apply rnd_of_unop_shift_incr in H1.
  apply rnd_of_unop_shift_le in H3; try lia.
  apply in_app_or in H0.
  destruct H0.
  {
    eapply rnd_of_unop_with_cond_shift_cond; eauto.
  }
  eapply IHe in H0; [ | eassumption ] .
  lia.
Qed.

Lemma sterbenz_no_overflow A x y:
  - A < x < A ->
  - A < y < A ->
  0 <= y * 2 - x ->
  0 <= x - y * / 2 ->
  - A < x - y < A
.
Proof.
  lra.
Qed.

Theorem fop_of_rounded_binop_correct op shift errors
        (Herr: forall i (ty' : type) (k : rounding_knowledge'),
                 mget shift i = (ty', k) ->
                 Rabs (errors i) <= error_bound ty' k)
        ty e1
        (F1: is_finite _ _ e1 = true)
        env r1
        (V1: reval r1 env errors =
             B2R _ _ e1)
        e2
        (F2: is_finite _ _ e2 = true)
        r2
        (V2: reval r2 env errors = B2R _ _ e2)
        r
        (V_: reval r env errors =
            Generic_fmt.round Zaux.radix2
                                    (FLT.FLT_exp
                                       (3 - femax ty - fprec ty)
                                       (fprec ty)
                                    )
                                    (Generic_fmt.Znearest (fun x : Z => negb (Z.even x)))
                                    (reval (RBinop (Rbinop_of_rounded_binop op) r1 r2) env errors))
        (COND:
           (forall i,
              In i ((if is_div op
                     then (RUnop Tree.Abs r2, true) :: nil
                     else nil)) ->
              eval_cond1 env shift i))
        (NO_OVERFLOW:
           eval_cond1 env shift (no_overflow ty r))
:
  is_finite _ _ (fop_of_rounded_binop op ty e1 e2) = true /\
  B2R _ _ (fop_of_rounded_binop op ty e1 e2) =
  reval r env errors.
Proof.
  intros.
  specialize (NO_OVERFLOW _ Herr).
  simpl in NO_OVERFLOW.
  rewrite Rmult_1_l in NO_OVERFLOW.
  rewrite V_ in * |- *.
  clear r V_.
  repeat rewrite B2R_correct in *.
  destruct op;
    cbn -[Zminus] in * |- * ;
    rewrite V1 in * |- *;
    rewrite V2 in * |- *.

  {
    (* plus *)
    generalize (Bplus_correct _ _  (fprec_gt_0 _) (fprec_lt_femax _) (plus_nan _) mode_NE _ _ F1 F2).
    rewrite Raux.Rlt_bool_true by (unfold round_mode; lra).
    destruct 1 as (? & ? & _).
    auto.
  }
  {
    (* minus *)
    generalize (Bminus_correct _ _  (fprec_gt_0 _) (fprec_lt_femax _) (plus_nan _) mode_NE _ _ F1 F2).
    rewrite Raux.Rlt_bool_true by (unfold round_mode; lra).
    destruct 1 as (? & ? & _).
    auto.
  }
  {
    (* mult *)
    generalize (Bmult_correct _ _ (fprec_gt_0 _) (fprec_lt_femax _) (mult_nan _) mode_NE e1 e2).
    rewrite Raux.Rlt_bool_true by (unfold round_mode; lra).
    rewrite F1. rewrite F2.
    simpl andb.
    destruct 1 as (? & ? & _).
    auto.
  }
  (* div *)
  generalize (fun K => Bdiv_correct _ _ (fprec_gt_0 _) (fprec_lt_femax _) (div_nan _) mode_NE e1 e2 K).
  rewrite Raux.Rlt_bool_true by (unfold round_mode; lra).
  rewrite F1.
  destruct 1 as (? & ? & _).
  {
    specialize (COND _ (or_introl _ (refl_equal _))).
    simpl in COND.
    specialize (COND _ Herr).
    apply Rabs_lt_pos in COND.
    congruence.
  }
  auto.
Qed.

Theorem fop_of_rounded_unop_correct shift errors
        (Herr: forall (i : nat) (ty' : type) (k : rounding_knowledge'),
                 mget shift i = (ty', k) ->
                 Rabs (errors i) <= error_bound ty' k)
        ty e1
        (F1: is_finite _ _ e1 = true)
        env r1
        (V1: reval r1 env errors =
             B2R _ _ e1)
        r
        (V_: reval r env errors =
            Generic_fmt.round Zaux.radix2
                                    (FLT.FLT_exp
                                       (3 - femax ty - fprec ty)
                                       (fprec ty)
                                    )
                                    (Generic_fmt.Znearest (fun x : Z => negb (Z.even x)))
                                    (reval (Runop_of_rounded_unop ty SQRT r1) env errors))
        (COND:
           (forall i,
              In i ((r1, false) :: nil) ->
              eval_cond1 env shift i))
:
  is_finite _ _ (fop_of_rounded_unop SQRT ty e1) = true /\
  B2R _ _ (fop_of_rounded_unop SQRT ty e1) =
  reval r env errors.
Proof.
  intros.
  rewrite V_ in * |- *.
  clear r V_.
  repeat rewrite B2R_correct in *.
    cbn -[Zminus] in * |- * ;
    rewrite V1 in * |- *.
    generalize (Bsqrt_correct _ _  (fprec_gt_0 _) (fprec_lt_femax _) (sqrt_nan _) mode_NE e1).
    destruct 1 as (? & ? & _).
    split; auto.
    specialize (COND _ (or_introl _ (refl_equal _))).
    simpl in COND.
    specialize (COND _ Herr).
    rewrite V1 in COND.
    clear r1 V1.
    destruct e1; auto.
    destruct s; auto.
    exfalso.
    revert COND.
    clear.
    simpl.
    clear e0.
    unfold Defs.F2R.
    simpl.
    assert (0 < INR (Pos.to_nat m) * Raux.bpow Zaux.radix2 e).
    {
      apply Rmult_lt_0_compat.
      {
        apply pos_INR_nat_of_P.
      }
      apply Raux.bpow_gt_0.
    }
   rewrite INR_IZR_INZ in H.
   intro.
   replace (IZR (Z.neg m)) with (- IZR (Z.of_nat (Pos.to_nat m))) in COND.
   lra.
   rewrite <- opp_IZR.
   f_equal.
   rewrite <- Pos2Z.opp_pos.
   f_equal.
   apply positive_nat_Z.
Qed.

Lemma rndval_with_cond_correct_uInvShift:
forall (env : forall x : type, V -> binary_float (fprec x) (femax x))
 (Henv : forall (ty : type) (i : V),  is_finite (fprec ty) (femax ty) (env ty i) = true)
(pow : positive)
 (ltr : bool) (e : expr) (si : nat) (r1 : rexpr) (s1 : MSHIFT)
 (errors1 errors1_1 : nat -> R)
 (E1 : forall i : nat, (i < si)%nat -> errors1_1 i = errors1 i)
 (EB1 : forall (i : nat) (ty' : type) (k : rounding_knowledge'),
      mget s1 i = (ty', k) -> Rabs (errors1_1 i) <= error_bound ty' k)
 (F1 : is_finite (fprec (type_of_expr e)) (femax (type_of_expr e)) (fval env e) = true)
 (V1 : reval r1 env errors1_1 =
         B2R (fprec (type_of_expr e)) (femax (type_of_expr e)) (fval env e))
 (H0 : expr_valid e = true)
 (shift : MSHIFT) (r : rexpr) (si2 : nat) (s : MSHIFT) (si1 : nat) (p1 : list cond) 
 (EQ1 : rndval_with_cond' si shift e = (r1, (si1, s1), p1))
 (p_ : list (rexpr * bool))
  (EQ : rnd_of_unop_with_cond si1 s1 (type_of_expr e) (Rounded1 (InvShift pow ltr) None) r1 =
     (r, (si2, s), p_))
 (H1 : forall i : cond, In i (p_ ++ p1) -> eval_cond1 env s i) 
 (H2 : forall (i : nat) (ty : type) (k : rounding_knowledge'),
     mget shift i = (ty, k) -> Rabs (errors1 i) <= error_bound ty k)
 (K_ : rnd_of_unop si1 s1 (type_of_expr e) (Rounded1 (InvShift pow ltr) None) r1 = (r, (si2, s))),
exists errors2 : nat -> R,
  (forall i : nat, (i < si)%nat -> errors2 i = errors1 i) /\
  (forall (i : nat) (ty' : type) (k : rounding_knowledge'),
   mget s i = (ty', k) -> Rabs (errors2 i) <= error_bound ty' k) /\
  is_finite (fprec (type_of_expr e)) (femax (type_of_expr e))
    (fop_of_unop (Rounded1 (InvShift pow ltr) None) (type_of_expr e) (fval env e)) = true /\
  reval r env errors2 =
  B2R (fprec (type_of_expr e)) (femax (type_of_expr e))
    (fop_of_unop (Rounded1 (InvShift pow ltr) None) (type_of_expr e) (fval env e)).
Proof.
intros.
assert (K1 := rndval_with_cond_left e si shift); rewrite EQ1 in K1; simpl in K1; symmetry in K1.
inversion EQ; clear EQ; subst.
set (op := RBinop Tree.Mul _) in *.
set (s := mset s1 si1 (type_of_expr e, Denormal')) in *.
pose (eps :=
  B2R (fprec (type_of_expr e)) (femax (type_of_expr e))
    (fop_of_unop (Rounded1 (InvShift pow ltr) None) (type_of_expr e) (fval env e)) -
  F2R radix2 (B2F (B2 (type_of_expr e) (Z.neg pow))) * reval r1 env errors1_1).
pose (errors2 i := if Nat.eq_dec i si1  then eps else errors1_1 i).
exists errors2.
split; [ | split; [ | split]].
-
intros. unfold errors2.
destruct (Nat.eq_dec i si1); auto.
pose proof (rndval_shift_incr _ _ _ _ _ _ K1). lia.
-
subst errors2.
simpl.
intros.
subst s; simpl in H.
rewrite (mget_set Nat.eq_dec) in H.
destruct (Nat.eq_dec i si1). inversion H; clear H; subst.
 +
  unfold error_bound.
  subst eps.
  rewrite V1.
 rewrite bpow_plus.
 rewrite <- Rmult_assoc.
 change (bpow radix2 1) with 2.
 rewrite Rinv_l, Rmult_1_l by lra.
 apply InvShift_accuracy; auto.
 +
  clear eps.
  destruct (le_lt_dec si i).
 *
  apply EB1; auto.
 *  rewrite E1 by auto. apply H2.
   rewrite <- H.
   symmetry; eapply rndval_shift_unchanged; eauto.
- apply InvShift_finite; auto.
-
 subst op. unfold reval; fold reval.
 replace (reval r1 env errors2) with (reval r1 env errors1_1).
2:{
   apply reval_error_ext; intros.
   unfold errors2.
 destruct (Nat.eq_dec i si1); auto.
  subst i.
  pose proof (rndval_shift_le _ _ _ _ _ _ K1). lia.
}
  subst errors2.
  subst eps.
  rewrite V1.
  simpl.
  destruct (Nat.eq_dec si1 si1) as [ _ |]; [ | congruence].
  set (a := F2R _ _).
  set (b := B2R _ _ _).
  set (c := B2R _ _ _).
  ring.
Qed.

Theorem rndval_with_cond_correct' env (Henv: forall ty i, is_finite _ _ (env ty i) = true) e:
  expr_valid e = true ->
  forall si shift r si2 s p,
    rndval_with_cond' si shift e = ((r, (si2, s)), p) ->
    (forall i, In i p -> eval_cond1 env s i) ->
    forall errors1,
      (forall i ty k,
         mget shift i = (ty, k) ->
         Rabs (errors1 i) <= error_bound ty k) ->
      exists errors2,
        (forall i,
           (i < si)%nat ->
           errors2 i = errors1 i)
        /\
        (forall i ty' k,
           mget s i = (ty', k) ->
           Rabs (errors2 i) <= error_bound ty' k)
        /\
        let fv := fval env e in
        is_finite _ _ fv = true
        /\
        reval r env errors2 = B2R _ _ fv
.
Proof.
  induction e; intros.
-  (* const *)
    simpl in *.
    inversion H0; clear H0; subst.
    simpl.
    exists errors1.
    split; auto.
    split; auto.
    split; auto.
    symmetry.
    rewrite F2R_eq.
    apply B2F_F2R_B2R.
- (* var *)
    simpl in *.
    inversion H0; clear H0; subst.
    eauto.
-  (* binop *)
    simpl in *.
    destruct (rndval_with_cond' si shift e1) as [[r1 [si1 s1]] p1] eqn:EQ1.
    destruct (rndval_with_cond' si1 s1 e2) as [[r2 [si2_ s2]] p2] eqn:EQ2.
    destruct (rnd_of_binop_with_cond si2_ s2 (type_lub (type_of_expr e1) (type_of_expr e2)) b r1 r2) as [rs p_] eqn:EQ.
    inversion H0; clear H0; subst.
    rewrite andb_true_iff in H.
    destruct H.

    assert (K1 := rndval_with_cond_left e1 si shift).
    rewrite EQ1 in K1.
    symmetry in K1.
    simpl in K1.
    generalize (rndval_with_cond_left e2 si1 s1).
    rewrite EQ2.
    intro K2.
    symmetry in K2.
    simpl in K2.
    generalize (rnd_of_binop_with_cond_left si2_ s2 (type_lub (type_of_expr e1) (type_of_expr e2)) b r1 r2).
    intro K_.
    rewrite EQ in K_.
    simpl in K_.
    symmetry in K_.

   assert (N : forall i : cond, In i p1 -> eval_cond1 env s1 i).
    {
      intros. 
      apply (eval_cond1_preserved s).
      {
        intros.
        subst.
        symmetry.
        etransitivity.
        {
          eapply rnd_of_binop_shift_unchanged; eauto.
          eapply lt_le_trans; [ eassumption | ].
          etransitivity.
          eapply rndval_with_cond_shift_cond; [ | eassumption ] ; eauto.
          eapply rndval_shift_incr; eauto.
        }
        eapply rndval_shift_unchanged; eauto.
        eapply lt_le_trans; [ eassumption | ].
        eapply rndval_with_cond_shift_cond; eauto.
      }
      apply H1. apply in_or_app. right. apply in_or_app. auto.
    }
    specialize (IHe1 H _ _ _ _ _ _ EQ1 N _ H2).
    clear N.
    destruct IHe1 as (errors1_1 & E1 & EB1 & F1 & V1).
    assert (N : forall i : cond, In i p2 -> eval_cond1 env s2 i).
    {
      intros.
      apply (eval_cond1_preserved s).
      {
        intros.
        subst.
        symmetry.
        eapply rnd_of_binop_shift_unchanged; eauto.
        eapply lt_le_trans; [ eassumption | ].
        eapply rndval_with_cond_shift_cond; [ | eassumption ] ; eauto.
      }
      apply H1. apply in_or_app. right. apply in_or_app. auto.
    }
    specialize (IHe2 H0 _ _ _ _ _ _ EQ2 N _ EB1).
    clear N.
    destruct IHe2 as (errors1_2 & E2 & EB2 & F2 & V2).

    generalize (cast_finite _ _ (type_lub_left _ (type_of_expr e2)) _ F1).
    generalize (cast_eq _ _ (type_lub_left _ (type_of_expr e2)) _ F1).
    clear F1.
    rewrite <- V1.
    clear V1.
    intros V1 F1.
    generalize (cast_finite _ _ (type_lub_right (type_of_expr e1) _) _ F2).
    generalize (cast_eq _ _ (type_lub_right (type_of_expr e1) _) _ F2).
    clear F2.
    rewrite <- V2.
    clear V2.
    intros V2 F2.
    symmetry in V1.
    symmetry in V2.

    rewrite <- (reval_error_ext errors1_2) in V1
     by (intros; apply E2; eapply lt_le_trans; [ eassumption | eapply rndval_shift_le; eauto]).
    destruct b.
   + (* rounded binary operator *)
        simpl.
        simpl in EQ.
        destruct (
            make_rounding si2_ s2 (round_knowl_denote knowl)
                          (type_lub (type_of_expr e1) (type_of_expr e2))
                          (RBinop (Rbinop_of_rounded_binop op) r1 r2)
          ) eqn:ROUND.
        inversion EQ; clear EQ; subst.
        simpl.

        generalize (make_rounding_correct _ _ _ _ _ _ _ _ ROUND).
        intro K.
        simpl max_error_var in K.
        assert (L: (Nat.max (max_error_var r1) (max_error_var r2) <= si2_)%nat).
        {
          intros.
          apply Nat.max_lub.
          {
            eapply le_trans; [ eapply rndval_shift_le; eauto | ].
            eapply rndval_shift_incr; eauto.
          }
          eapply rndval_shift_le; eauto.
        }
        specialize (K L _ EB2).
        clear L.
        assert (L: rounding_cond (type_lub (type_of_expr e1) (type_of_expr e2)) (round_knowl_denote knowl)
                            (reval (RBinop (Rbinop_of_rounded_binop op) r1 r2) env errors1_2)).
        {
          eapply rounding_cond_ast_correct; [ eassumption | ].
          intros.
          eapply (eval_cond1_preserved s).
          {
            intros.
            subst.
            symmetry.
            apply rounding_cond_ast_shift in H3.
            simpl in H3.
            
            eapply make_rounding_shift_unchanged; eauto.
            eapply lt_le_trans; eauto.
            etransitivity; try eassumption.
            apply Max.max_lub; eauto using rndval_shift_le.
            etransitivity; [ eapply rndval_shift_le; eauto | ].
            eapply rndval_shift_incr; eauto.
          }
          eapply H1. apply in_or_app. left. apply in_or_app. right. right. assumption.
        }
        specialize (K _ L (fun x : Z => negb (Z.even x))).
        clear L.
        destruct K as (errors2 & E & R & EB).
        assert (W1: reval r1 env errors2 = reval r1 env errors1_2). {
          apply reval_error_ext.
          intros.
          apply E.
          eapply lt_le_trans; [ eassumption | ].
          etransitivity; [ eapply rndval_shift_le; eauto | ].
          eapply rndval_shift_incr; eauto.
        }

        assert (W2: reval r2 env errors2 = reval r2 env errors1_2). {
          apply reval_error_ext.
          intros.
          apply E.
          eapply lt_le_trans; [ eassumption | ].
          eapply rndval_shift_le; eauto.
        }
        rewrite <- W1, <- W2 in *.
        assert (
            reval (RBinop (Rbinop_of_rounded_binop op) r1 r2) env errors1_2
            =
            reval (RBinop (Rbinop_of_rounded_binop op) r1 r2) env errors2
        ) as W.
        {
          simpl.
          congruence.
        }
        rewrite W in * |- *. clear W.

        assert (L : forall i : rexpr * bool,
             In i (if is_div op then (RUnop Tree.Abs r2, true) :: nil else nil) ->
             eval_cond1 env s i).
        {
          intros.
          apply H1.
          apply in_or_app.
          left.
          apply in_or_app.
          auto.
        }
       assert (L': eval_cond1 env s
            (no_overflow (type_lub (type_of_expr e1) (type_of_expr e2)) r)).
        {
          apply H1.
          apply in_or_app.
          left.
          apply in_or_app.
          right.
          left.
          auto.
        }

        assert (K := fop_of_rounded_binop_correct _ _ _ EB 
                                                 _ _ F1
                                                 _ _ V1
                                                 _ F2
                                                 _ V2
                                                 _ R L L').
        clear L L'.

        destruct K.
        exists errors2.
        split; auto.
        intros.
        etransitivity.
        {
          eapply E.
          eapply lt_le_trans; [ eassumption | ].
          etransitivity; [ eapply rndval_shift_incr; eauto | ].
          eapply rndval_shift_incr; eauto.
        }
        etransitivity.
        {
          eapply E2.
          eapply lt_le_trans; [ eassumption | ].
          eapply rndval_shift_incr; eauto.
        }
        eauto.
    + (* Sterbenz *)      
        simpl.
        simpl in EQ.
        inversion EQ; clear EQ; subst.
        simpl.
        generalize (H1 _ (or_introl _ (refl_equal _))).
        specialize (fun j K => H1 j (or_intror _ K)).
        specialize (H1 _ (or_introl _ (refl_equal _))).
        simpl in H1 |- * .
        intro H1'.
        rewrite Rmult_1_l in *.
        specialize (H1 _ EB2).
        specialize (H1' _ EB2).

        generalize (Bminus_correct _ _  (fprec_gt_0 _) (fprec_lt_femax _) (plus_nan _) mode_NE _ _ F1 F2).
        intro K.
        change ( Z.pos
                   (fprecp (type_lub (type_of_expr e1) (type_of_expr e2))))
        with (
          fprec (type_lub (type_of_expr e1) (type_of_expr e2))
        ) in K.
        rewrite <- V1 in K.
        rewrite <- V2 in K.
        rewrite Generic_fmt.round_generic in K; try typeclasses eauto.
        {
          destruct (Rlt_dec
                      (Rabs (reval r1 env errors1_2 - reval r2 env errors1_2))
                      (Raux.bpow Zaux.radix2
                                       (femax (type_lub (type_of_expr e1) (type_of_expr e2))))
                   ).
          {
            apply Raux.Rlt_bool_true in r.
            rewrite r in K.
            destruct K as (KR & KF & _).
            exists errors1_2.
            split; auto.
            intros.
            etransitivity.
            {
              eapply E2.
              eapply lt_le_trans; [ eassumption | ].
              eapply rndval_shift_incr; eauto.
            }
            auto.
          }
          exfalso.
          pose proof 
          (abs_B2R_lt_emax _ _
            (cast (type_lub (type_of_expr e1) (type_of_expr e2)) 
                  (type_of_expr e1) (fval env e1))).
          pose proof 
          (abs_B2R_lt_emax _ _
            (cast (type_lub (type_of_expr e1) (type_of_expr e2)) 
                  (type_of_expr e2) (fval env e2))).
          rewrite <- V1 in H3.
          rewrite <- V2 in H4.
          apply Raux.Rabs_lt_inv in H3.
          apply Raux.Rabs_lt_inv in H4.
          generalize (sterbenz_no_overflow _ _ _ H3 H4 H1 H1').
          clear K.
          intro K.
          apply Raux.Rabs_lt in K.
          contradiction.
        }
        apply Sterbenz.sterbenz; try typeclasses eauto.
        * rewrite V1. apply generic_format_B2R.
        * rewrite V2. apply generic_format_B2R.
        * lra.

    + (* plus zero *)
        simpl.
        simpl in EQ.
        inversion EQ; clear EQ; subst.
        simpl.
        specialize (H1 _ (or_introl _ (refl_equal _))).
        simpl in H1 |- * .
        specialize (H1 _ EB2).        
        exists errors1_2.
        split.
        *
          intros.
          etransitivity.
          {
            eapply E2.
            eapply lt_le_trans; [ eassumption | ].
            eapply rndval_shift_incr; eauto.
          }
          eauto.
        * split; auto.
         assert (reval (if zero_left then r1 else r2) env errors1_2 = 0) as ZERO.
         {
          rewrite <- Rabs_zero_iff.
          apply Rle_antisym; [lra | ].
          apply Rabs_pos.
         }
         destruct zero_left.
         {
          rewrite V1 in ZERO.
          pose proof (abs_B2R_lt_emax _ _
          (cast (type_lub (type_of_expr e1) (type_of_expr e2)) 
            (type_of_expr e2) (fval env e2))).
          destruct minus.
          {
            generalize (Bminus_correct _ _  (fprec_gt_0 _) (fprec_lt_femax _) (plus_nan _) mode_NE _ _ F1 F2).
            rewrite ZERO.
            rewrite Rminus_0_l.
            rewrite Generic_fmt.round_opp.
            rewrite Generic_fmt.round_generic; try typeclasses eauto.
            {
              rewrite Rabs_Ropp.
              rewrite Raux.Rlt_bool_true by assumption.
              unfold BMINUS.
              unfold BINOP.
              simpl reval.
              destruct 1 as (BV & BF & _).
              simpl femax in BV, BF |- * .
              unfold cast_lub_l.
              unfold cast_lub_r.
              rewrite BV.
              intuition.
            }
            apply generic_format_B2R.
          }
          generalize (Bplus_correct _ _  (fprec_gt_0 _) (fprec_lt_femax _) (plus_nan _) mode_NE _ _ F1 F2).
          rewrite ZERO.
          rewrite Rplus_0_l.
          rewrite Generic_fmt.round_generic; try typeclasses eauto.
          {
            rewrite Raux.Rlt_bool_true by assumption.
            unfold BPLUS.
            unfold BINOP.
            simpl reval.
            destruct 1 as (BV & BF & _).
            simpl femax in BV, BF |- * .
            unfold cast_lub_l.
            unfold cast_lub_r.
            rewrite BV.
            intuition.
          }
          apply generic_format_B2R.          
        }
        rewrite V2 in ZERO.
        pose proof (abs_B2R_lt_emax _ _
        (cast (type_lub (type_of_expr e1) (type_of_expr e2)) 
          (type_of_expr e1) (fval env e1))).
        destruct minus.
        {
          generalize (Bminus_correct _ _  (fprec_gt_0 _) (fprec_lt_femax _) (plus_nan _) mode_NE _ _ F1 F2).
          rewrite ZERO.
          rewrite Rminus_0_r.
          rewrite Generic_fmt.round_generic; try typeclasses eauto.
          {
            rewrite Raux.Rlt_bool_true by assumption.
            unfold BMINUS.
            unfold BINOP.
            simpl reval.
            destruct 1 as (BV & BF & _).
            simpl femax in BV, BF |- * .
            unfold cast_lub_l.
            unfold cast_lub_r.
            rewrite BV.
            intuition.
          }
          apply generic_format_B2R.
        }
        generalize (Bplus_correct _ _  (fprec_gt_0 _) (fprec_lt_femax _) (plus_nan _) mode_NE _ _ F1 F2).
        rewrite ZERO.
        rewrite Rplus_0_r.
        rewrite Generic_fmt.round_generic; try typeclasses eauto.
        {
          rewrite Raux.Rlt_bool_true by assumption.
          unfold BPLUS.
          unfold BINOP.
          simpl reval.
          destruct 1 as (BV & BF & _).
          simpl femax in BV, BF |- * .
          unfold cast_lub_l.
          unfold cast_lub_r.
          rewrite BV.
          intuition.
        }
        apply generic_format_B2R.          

- (* unop *)
  simpl in *.
  destruct (rndval_with_cond' si shift e) as [[r1 [si1 s1]] p1] eqn:EQ1.
  destruct (rnd_of_unop_with_cond si1 s1 (type_of_expr e) u r1) as [rs p_] eqn:EQ.
  inversion H0; clear H0; subst.
  rewrite andb_true_iff in H.
  destruct H.

  generalize (rndval_with_cond_left e si shift).
  rewrite EQ1.
  intro K1.
  symmetry in K1.
  simpl in K1.
  generalize (rnd_of_unop_with_cond_left si1 s1 (type_of_expr e) u r1).
  rewrite EQ.
  simpl.
  intro K_.
  symmetry in K_.

  assert (N: forall i : cond, In i p1 -> eval_cond1 env s1 i).
  {
    intros.
    apply (eval_cond1_preserved s).
    {
      intros; subst.
      symmetry.
      eapply rnd_of_unop_shift_unchanged; eauto.
      eapply lt_le_trans; eauto.
      eapply rndval_with_cond_shift_cond; eauto.
    }
    apply H1. apply in_or_app. auto.
  }
  specialize (IHe H0 _ _ _ _ _ _ EQ1 N _ H2).
  clear N.
  destruct IHe as (errors1_1 & E1 & EB1 & F1 & V1).

  destruct u.
 + (* rounded unary operator *)
    simpl.
  destruct op.
  * (* SQRT *)
    simpl in EQ.
    unfold Datatypes.id in *.
    destruct (
        make_rounding si1 s1 (round_knowl_denote knowl)
                      (type_of_expr e) (RUnop Tree.Sqrt r1)
      ) eqn:ROUND.
    inversion EQ; clear EQ; subst.

    assert (K := make_rounding_correct _ _ _ _ _ _ _ _ ROUND).
    simpl max_error_var in K.
    assert (L:  (max_error_var r1 <= si1)%nat).
    {
      intros.
      eapply rndval_shift_le; eauto.
    }
    assert (L': rounding_cond (type_of_expr e) (round_knowl_denote knowl)
      (reval (RUnop Tree.Sqrt r1)env errors1_1)).
    {
      eapply rounding_cond_ast_correct; [ eassumption | ].
      intros.
      eapply (eval_cond1_preserved s).
      {
        intros; subst.
        symmetry.
        apply rounding_cond_ast_shift in H3.
        simpl in H3.
        eapply rnd_of_unop_shift_unchanged; eauto.
        eapply lt_le_trans; eauto.
        etransitivity; try eassumption.
      }
      eapply H1.
      apply in_or_app.
      left.
      right.
      assumption.
    }
    specialize (K L _ EB1 _ L' (fun x : Z => negb (Z.even x))).
    clear L L'.
    destruct K as (errors2 & E & R & EB).

    assert (W1: reval r1 env errors2 = reval r1 env errors1_1).
    {
      apply reval_error_ext.
      intros.
      apply E.
      eapply lt_le_trans; [ eassumption | ].
      eapply rndval_shift_le; eauto.
    }
    rewrite <- W1 in V1.

    assert (
        reval (RUnop Tree.Sqrt r1) env errors1_1
        =
        reval (RUnop Tree.Sqrt r1) env errors2
      ) as W.
    {
      simpl.
      congruence.
    }
    rewrite W in * |- *. clear W.

   assert (L : forall i : rexpr * bool,
     In i ((r1, false) :: nil) ->
     eval_cond1 env s i).
    {
      intros.
      apply H1.
      apply in_or_app.
      left.   destruct H3. left; auto. destruct H3.
    }
    assert (K := fop_of_rounded_unop_correct _ _ EB 
                                             _ _ F1
                                             _ _ V1
                                             _ R L).
    clear L.

    destruct K.
    exists errors2.
    split; auto.
    intros.
    etransitivity.
    {
      eapply E.
      eapply lt_le_trans; [eassumption | ].
      eapply rndval_shift_incr; eauto.
    }
    eauto.
  * (* InvShift *)
   destruct knowl as [ [ | ] | ].
  -- (* Normal *)
    simpl.
    cbn -[Zminus] in EQ.
    unfold Datatypes.id in *.
    Opaque Zminus.
    inversion EQ; clear EQ; subst.
    Transparent Zminus.

    exists errors1_1.
    split; auto.
    split; auto.
    cbn -[Zminus] in * |- *.
    rewrite F2R_eq.
    rewrite <- B2F_F2R_B2R.
    rewrite Z.leb_le in H.
    apply center_Z_correct in H.
    assert (B2_FIN := B2_finite (type_of_expr e) (Z.neg pow) (proj2 H)).
    generalize (Bmult_correct _ _ (fprec_gt_0 _) (fprec_lt_femax _) (mult_nan _) mode_NE (B2 (type_of_expr e) (Z.neg pow)) (fval env e)).
    generalize (Bmult_correct_comm _ _ (fprec_gt_0 _) (fprec_lt_femax _) (mult_nan _) mode_NE (B2 (type_of_expr e) (Z.neg pow)) (fval env e)).
    rewrite Rmult_comm.
    generalize (B2_correct _ (Z.neg pow) H).
    repeat rewrite B2R_correct.
    intro K.
    rewrite K.
    replace (Z.neg pow) with (- Z.pos pow)%Z in * |- * by reflexivity.   
    rewrite Raux.bpow_opp.
    rewrite FLT_format_div_beta_1; try typeclasses eauto.
    {
      unfold Rdiv.
      rewrite <- Raux.bpow_opp.
      rewrite F1.
      rewrite B2_FIN.
      simpl andb.
      rewrite Raux.Rlt_bool_true.
      {
        unfold BMULT, BINOP.
        destruct 1 as (LC & ? & ?).
        destruct 1 as (L & ? & ?).
        destruct ltr; split; auto; rewrite V1.
        {
          rewrite LC.
          ring.
        }
        rewrite L.
        ring.
      }
      rewrite Raux.bpow_opp.
      apply Bdiv_beta_no_overflow.
      assumption.
    }
    specialize (H1 _ (or_introl _ (refl_equal _))).
    specialize (H1 _ EB1).
    cbn -[Zminus] in H1.
    rewrite <- V1.
    lra.
  -- eapply rndval_with_cond_correct_uInvShift; eassumption.
  -- eapply rndval_with_cond_correct_uInvShift; eassumption.

 + (* exact unary operator *)

    simpl.
    cbn -[Zminus] in EQ.
    unfold Datatypes.id in *.
    Opaque Zminus.
    inversion EQ; clear EQ; subst.
    Transparent Zminus.

    exists errors1_1.
    split; auto.
    split; auto.

    destruct o.

   * (* abs *)
      simpl in * |- *.
      unfold BABS.
      rewrite is_finite_Babs.
      split; auto.
      rewrite B2R_Babs.
      congruence.

   * (* opp *)
      simpl in * |- * .
      unfold BOPP.
      rewrite is_finite_Bopp.
      split; auto.
      rewrite B2R_Bopp.
      congruence.

   * (* shift *)
      cbn -[Zminus] in * |- *.
      rewrite F2R_eq.
      rewrite <- B2F_F2R_B2R.
      rewrite Z.leb_le in H.
      apply center_Z_correct in H.
      generalize (B2_finite (type_of_expr e) (Z.of_N pow) (proj2 H)).
      intro B2_FIN.
      generalize
          (Bmult_correct _ _ (fprec_gt_0 _) (fprec_lt_femax _) (mult_nan _) mode_NE (B2 (type_of_expr e) (Z.of_N pow)) (fval env e)).
      generalize
         (Bmult_correct_comm _ _ (fprec_gt_0 _) (fprec_lt_femax _) (mult_nan _) mode_NE (B2 (type_of_expr e) (Z.of_N pow)) (fval env e)).
      rewrite Rmult_comm.
      replace (Z.of_N (pow + 1)) with (Z.of_N pow + 1)%Z in H by (rewrite N2Z.inj_add; simpl; ring).
      assert (K := B2_correct _ _ H).
      rewrite K.
      rewrite FLT_format_mult_beta_n; try typeclasses eauto.
      rewrite F1.
      rewrite B2_FIN.
      simpl andb.
      rewrite Raux.Rlt_bool_true.
      {
        unfold BMULT, BINOP.
        destruct 1 as (LC & ? & ?).
        destruct 1 as (L & ? & ?).        
        destruct ltr; split; auto; rewrite V1.
        {
          rewrite LC.
          ring.
        }
        rewrite L.
        ring.
      }
      specialize (H1 _ (or_introl _ (refl_equal _))).
      specialize (H1 _ EB1).
      simpl in H1.
      rewrite F2R_eq in H1.
      rewrite <- B2F_F2R_B2R in H1.
      rewrite V1 in H1.
      rewrite K in H1.
      rewrite Rmult_comm.
      lra.

 + (* cast *)
  simpl.
  simpl in *.
  unfold cast.
  unfold rnd_of_cast_with_cond in EQ.
  destruct (type_eq_dec (type_of_expr e) ty).
  {
    subst ty.
    simpl.
    rewrite (fun t1 t2 => let (_, K) := type_leb_le t1 t2 in K) in EQ.
    {
      inversion EQ; clear EQ; subst.
      eauto.
    }
    apply type_le_refl.
  }
  destruct (type_leb (type_of_expr e) ty) eqn:LEB.
  {
    inversion EQ; clear EQ; subst.
    rewrite type_leb_le in LEB.
    inversion LEB.
    generalize ((fun J1 =>
                  Bconv_widen_exact _ _ _ _ J1 (fprec_gt_0 _) (fprec_lt_femax _) (Z.le_ge _ _ H3) (Z.le_ge _ _ H4) (conv_nan _ _) mode_NE _ F1) ltac:( typeclasses eauto ) ).
    destruct 1 as (K & L & _).
    symmetry in K.
    rewrite <- V1 in K.
    eauto.
  }
  destruct (make_rounding si1 s1 (round_knowl_denote knowl) ty r1) eqn:ROUND.
  inversion EQ; clear EQ; subst.
  generalize (make_rounding_correct _ _ _ _ _ _ _ _ ROUND).
  intro K.
  assert (L: (max_error_var r1 <= si1)%nat).
  {
    eapply rndval_shift_le; eauto.
  }
  assert (L': rounding_cond ty (round_knowl_denote knowl) (reval r1 env errors1_1)).
  {
    eapply rounding_cond_ast_correct.
    {
      eassumption.
    }
    intros.
    eapply (eval_cond1_preserved s).
    {
      intros; subst.
      symmetry.
      apply rounding_cond_ast_shift in H3.
      simpl in H3.
      eapply make_rounding_shift_unchanged; eauto.
      eapply lt_le_trans; eauto.
      etransitivity; try eassumption.
    }
    eapply H1.
    apply in_or_app.
    left.
    right.
    assumption.
  } 
  specialize (K L _ EB1 _ L'  (fun x : Z => negb (Z.even x))); clear L L'.
  destruct K as (errors2 & E & R & EB).
  rewrite V1 in R.
  generalize (Bconv_correct _ _ _ _ (fprec_gt_0 _) (fprec_lt_femax ty) (conv_nan _ _) mode_NE _ F1).
  unfold round_mode.
  rewrite <- R.
  rewrite Raux.Rlt_bool_true.
  {
    destruct 1 as (J & K & _).
    symmetry in J.
    exists errors2.
    split; auto.
    intros.
    etransitivity.
    {
      eapply E.
      eapply lt_le_trans; eauto.
      eapply rndval_shift_incr; eauto.
    }
    auto.
  }
  specialize (H1 _ (or_introl _ (refl_equal _))).
  specialize (H1 _ EB).
  simpl in H1.
  lra.
Qed.

Definition empty_shiftmap := mempty (Tsingle, Unknown').

Definition environ := forall ty : type, V -> ftype ty.

Definition env_all_finite (env: environ) :=
  forall (ty : type) (i : V),
        is_finite (fprec ty) (femax ty) (env ty i) = true.

Definition eval_cond (s: MSHIFT) (c: cond) (env: environ) : Prop :=
  eval_cond1 env s c.

Definition rndval_with_cond (e: expr) : rexpr * MSHIFT * list (environ -> Prop) :=
 let '((r,(si,s)),p) := rndval_with_cond' 0 empty_shiftmap e
  in (r, s, map (eval_cond s) p).

Definition errors_bounded
    (shift: MSHIFT) (errors: nat -> R) := 
   forall i ty k,
         mget shift i = (ty, k) ->
         (Rabs (errors i) <= error_bound ty k)%R.

Theorem rndval_with_cond_correct 
    env (Henv: env_all_finite env) (e: expr):
  expr_valid e = true ->
  forall r s p,
    rndval_with_cond e = (r, s, p) ->
    Forall (fun c => c env) p ->
    exists errors,
        (errors_bounded s errors)
        /\
        let fv := fval env e in
        is_finite _ _ fv = true
        /\
        reval r env errors = B2R _ _ fv
.
Proof.
intros.
unfold rndval_with_cond in H0.
destruct (rndval_with_cond' 0 empty_shiftmap e) as [[r' [si s']] p'] eqn:?H.
inversion H0; clear H0; subst r' s' p.
assert (forall i : cond, In i p' -> eval_cond1 env s i). {
  intros.
  rewrite Forall_forall in H1.
  apply H1. 
  rewrite in_map_iff.
  exists i; auto.
}
destruct (rndval_with_cond_correct' env Henv e H 0 empty_shiftmap r _ _ _ H2 H0
 (fun _ => 0%R))
  as [errors2 [? [? [? ?]]]].
-
intros.
unfold empty_shiftmap in H3.
rewrite mget_empty in H3.
inversion H3; clear H3; subst.
unfold error_bound.
simpl.
rewrite Rabs_R0.
lra.
-
exists errors2; split; auto.
Qed.

End WITHMAP.

End WITHVAR.

Section TEST.

Local Program Instance map_nat: MapIndex nat :=
  {
    index_of_tr := Pos.of_succ_nat
  }.
Next Obligation.
  generalize SuccNat2Pos.inj_iff.
  clear.
  firstorder.
Defined.

Local Existing Instances compcert_map.

(* OK
Definition sqrt_of_two : @expr ident := Unop (Rounded1 SQRT None) (Const Tsingle (B2 _ 0)).
Eval simpl in rndval 0 (Maps.PMap.init 0) sqrt_of_two.
Eval simpl in rndval_with_cond 0 (Maps.PMap.init 0) sqrt_of_two.
*)


End TEST.


