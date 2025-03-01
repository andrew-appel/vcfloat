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

VCFloat: helpers for correct optimization of rounding error terms in
the real-number semantics of floating-point computations.
**)

Require Export vcfloat.Float_lemmas.
Require Export vcfloat.FPLang.
Import RAux.
Import compcert.lib.IEEE754_extra.
Import compcert.lib.Floats.
Require Export vcfloat.LibTac.
Require Export vcfloat.BigRAux.
Set Bullet Behavior "Strict Subproofs". (* because LibTac screws it up *)

Definition rounded_binop_eqb (r1 r2: rounded_binop): bool :=
  match r1, r2 with
    | PLUS, PLUS => true
    | MINUS, MINUS => true
    | MULT, MULT => true
    | DIV, DIV => true
    | _, _ => false
  end.

Lemma rounded_binop_eqb_eq r1 r2:
  (rounded_binop_eqb r1 r2 = true <-> r1 = r2).
Proof.
  destruct r1; destruct r2; simpl; intuition congruence.
Qed.

Definition rounding_knowledge_eqb (r1 r2: rounding_knowledge): bool :=
  match r1, r2 with
    | Normal, Normal => true
    | Denormal, Denormal => true
    | _, _ => false
  end.

Lemma rounding_knowledge_eqb_eq r1 r2:
  (rounding_knowledge_eqb r1 r2 = true <-> r1 = r2).
Proof.
  destruct r1; destruct r2; simpl; try intuition congruence.
Qed.

Export Bool.

Definition binop_eqb b1 b2 :=
  match b1, b2 with
    | Rounded2 op1 k1, Rounded2 op2 k2 =>
      rounded_binop_eqb op1 op2 && option_eqb rounding_knowledge_eqb k1 k2
    | SterbenzMinus, SterbenzMinus => true
    | PlusZero minus1 zero_left1, PlusZero minus2 zero_left2 =>
      Bool.eqb minus1 minus2 && Bool.eqb zero_left1 zero_left2
    | _, _ => false
  end.

Lemma binop_eqb_eq b1 b2:
  (binop_eqb b1 b2 = true <-> b1 = b2).
Proof.
  destruct b1; destruct b2; simpl; (try intuition congruence);
  rewrite andb_true_iff;
    (try rewrite rounded_binop_eqb_eq);
    (try rewrite (option_eqb_eq rounding_knowledge_eqb_eq));
    (repeat rewrite Bool.eqb_true_iff);
  intuition congruence.
Qed.

Definition rounded_unop_eqb u1 u2 :=
  match u1, u2 with
    | SQRT, SQRT => true
    | InvShift p1 b1, InvShift p2 b2 => Pos.eqb p1 p2 && Bool.eqb b1 b2
    | _, _ => false
  end.

Lemma rounded_unop_eqb_eq u1 u2:
  (rounded_unop_eqb u1 u2 = true <-> u1 = u2).
Proof.
  destruct u1; destruct u2; simpl; try intuition congruence.
  rewrite Bool.andb_true_iff;
  (try rewrite Pos.eqb_eq);
  (try rewrite N.eqb_eq);
  rewrite Bool.eqb_true_iff;
  intuition congruence.
Qed.


Definition exact_unop_eqb u1 u2 :=
  match u1, u2 with
    | Abs, Abs => true
    | Opp, Opp => true
    | Shift p1 b1, Shift p2 b2  => N.eqb p1 p2 && Bool.eqb b1 b2
    | _, _ => false
  end.

Lemma exact_unop_eqb_eq u1 u2:
  (exact_unop_eqb u1 u2 = true <-> u1 = u2).
Proof.
  destruct u1; destruct u2; simpl; (try intuition congruence);
  rewrite Bool.andb_true_iff;
  (try rewrite Pos.eqb_eq);
  (try rewrite N.eqb_eq);
  rewrite Bool.eqb_true_iff;
  intuition congruence.
Qed.

Definition unop_eqb u1 u2 :=
  match u1, u2 with
    | Rounded1 op1 k1, Rounded1 op2 k2 =>
      rounded_unop_eqb op1 op2 && option_eqb rounding_knowledge_eqb k1 k2
    | Exact1 o1, Exact1 o2 => exact_unop_eqb o1 o2
    | CastTo ty1 k1, CastTo ty2 k2 =>
      type_eqb ty1 ty2 && option_eqb rounding_knowledge_eqb k1 k2
    | _, _ => false
  end.

Lemma unop_eqb_eq u1 u2:
  (unop_eqb u1 u2 = true <-> u1 = u2).
Proof.
  destruct u1; destruct u2; simpl; (try intuition congruence).
-
    rewrite andb_true_iff.
    rewrite rounded_unop_eqb_eq.
    rewrite (option_eqb_eq rounding_knowledge_eqb_eq).
    intuition congruence.
-
    rewrite exact_unop_eqb_eq.
    intuition congruence.
-
  rewrite andb_true_iff.
  rewrite type_eqb_eq.
  rewrite (option_eqb_eq rounding_knowledge_eqb_eq).
  intuition congruence.
Qed.

Section WITHVARS.
Context {V} `{VARS: VarType V}.

Context {NANS: Nans}.

Definition fcval_nonrec (e: expr): option (ftype (type_of_expr e)) :=
  match e as e' return option (ftype (type_of_expr (V := V) e')) with
    | Const ty f => Some f
    | _ => None
  end.

Lemma fcval_nonrec_correct e:
  forall v, fcval_nonrec e = Some v ->
            forall env, fval env e = v.
Proof.
  destruct e; simpl; try discriminate.
  intros; congruence.
Qed.

Definition option_pair_of_options {A B} (a: option A) (b: option B) :=
  match a, b with
    | Some a', Some b' => Some (a', b')
    | _, _ => None
  end.

Lemma option_pair_of_options_correct {A B} (a: option A) (b: option B) a' b':
  option_pair_of_options a b = Some (a', b') ->
  a = Some a' /\ b = Some b'.
Proof.
  unfold option_pair_of_options.
  destruct a; destruct b; intuition congruence.
Qed.

(* Partial evaluation of constants *)

Fixpoint fcval (e: expr) {struct e}: expr :=
  match e with
    | Binop b e1 e2 =>
      let e'1 := fcval e1 in
      let e'2 := fcval e2 in
      match option_pair_of_options (fcval_nonrec e'1) (fcval_nonrec e'2) with
        | Some (v1, v2) =>
          Const _ (fop_of_binop b _ (cast_lub_l _ _ v1) (cast_lub_r _ _ v2))
        | None => Binop b e'1 e'2
      end
    | Unop b e =>
      let e' := fcval e in
      match fcval_nonrec e' with
        | Some v => Const _ (fop_of_unop b _ v)
        | _ => Unop b e'
      end
    | _ => e
  end.

Lemma fcval_type e:
  type_of_expr (fcval e) = type_of_expr e.
Proof.
  induction e; simpl; auto.
  {
    destruct (fcval_nonrec (fcval e1)) eqn:EQ1; simpl; try congruence.
    destruct (fcval_nonrec (fcval e2)) eqn:EQ2; simpl; congruence.
  }
  destruct (fcval_nonrec (fcval e)) eqn:EQ; simpl; congruence.
Defined. (* required because of eq_rect_r *)

Lemma fcval_correct_bool env e:
  binary_float_eqb (fval env (fcval e)) (fval env e) = true.
Proof.
  induction e; simpl.
  {
    apply binary_float_eqb_eq. reflexivity.
  }
  {
    apply binary_float_eqb_eq. reflexivity.
  }
  {
    destruct (option_pair_of_options (fcval_nonrec (fcval e1)) (fcval_nonrec (fcval e2))) eqn:OPT.
    {
      destruct p.
      apply option_pair_of_options_correct in OPT.
      destruct OPT as (V1 & V2).
      apply fcval_nonrec_correct with (env := env) in V1.
      apply fcval_nonrec_correct with (env := env) in V2.
      simpl.
      unfold cast_lub_l, cast_lub_r.
      subst.
      revert IHe1 IHe2.
      generalize (fval env (fcval e1)).
      generalize (fval env e1).
      generalize (fval env (fcval e2)).
      generalize (fval env e2).
      rewrite fcval_type.
      rewrite fcval_type.
      intros ? ? ? ? .
      repeat rewrite binary_float_eqb_eq.
      congruence.
    }
    clear OPT.
    simpl.
    unfold cast_lub_l, cast_lub_r.
    subst.
    revert IHe1 IHe2.
    generalize (fval env (fcval e1)).
    generalize (fval env e1).
    generalize (fval env (fcval e2)).
    generalize (fval env e2).
    rewrite fcval_type.
    rewrite fcval_type.
    intros ? ? ? ? .
    repeat rewrite binary_float_eqb_eq.
    congruence.
  }    
  destruct (fcval_nonrec (fcval e)) eqn:V_.
  {
    apply fcval_nonrec_correct with (env := env) in V_.
    subst.
    revert IHe.
    generalize (fval env (fcval e)).
    generalize (fval env e).
    rewrite fcval_type.
    intros ? ? .
    simpl.
    repeat rewrite binary_float_eqb_eq.
    congruence.
  }
  simpl.
  revert IHe.
  generalize (fval env (fcval e)).
  generalize (fval env e).
  rewrite fcval_type.
  intros ? ? .
  simpl.
  repeat rewrite binary_float_eqb_eq.
  congruence.
Qed.  

Lemma binary_float_eqb_eq_strong ty1 ty2 (e1: ftype ty1) (e2: ftype ty2):
  binary_float_eqb e1 e2 = true ->
  forall EQ: ty1 = ty2,
    binary_float_eqb e1 (eq_rect_r _ e2 EQ) = true.
Proof.
  intros.
  subst.
  assumption.
Qed.

(*
Lemma binary_float_eqb_equiv_strong ty (e1 e2: ftype ty):
  binary_float_equiv e1 e2 ->
  forall EQ: ty1 = ty2,
    binary_float_equiv e1 (eq_rect_r _ e2 EQ).
Proof.
  intros.
  subst.
  assumption.
Qed.
  *)
      
Lemma fcval_correct env e:
  fval env (fcval e) = eq_rect_r _ (fval env e) (fcval_type e).
Proof.
  apply binary_float_eqb_eq.
  apply binary_float_eqb_eq_strong.
  apply fcval_correct_bool.
Qed.

Lemma is_finite_eq_rect_r ty1 ty2 (f: ftype ty2)
      (EQ: ty1 = ty2):
  Binary.is_finite _ _ (eq_rect_r _ f EQ) = Binary.is_finite _ _ f.
Proof.
  subst.
  reflexivity.
Qed.

Lemma B2R_eq_rect_r ty1 ty2 (f: ftype ty2)
      (EQ: ty1 = ty2):
  Binary.B2R _ _ (eq_rect_r _ f EQ) = Binary.B2R _ _ f.
Proof.
  subst.
  reflexivity.
Qed.

Import Qreals.
Open Scope R_scope.

(* Identification of shifts *)
Definition F2BigQ (beta : Zaux.radix) (f : Defs.float beta) :=
  match f with
    | {| Defs.Fnum := Fnum; Defs.Fexp := Fexp |} =>
      BigQ.mul (BigQ.Qz (BigZ.of_Z Fnum)) (BigQ.power (BigQ.Qz (BigZ.of_Z (Zaux.radix_val beta))) Fexp)
  end.

Lemma Q2R_Qpower_positive p:
  forall q,
    Q2R (Qpower_positive q p) = Q2R q ^ Pos.to_nat p.
Proof.
  induction p.
  {
    intros.
    rewrite Pos2Nat.inj_xI.
    simpl.
    repeat rewrite pow_add.
    simpl.
    repeat rewrite Q2R_mult.
    repeat rewrite IHp.
    ring.
  }
  {
    intros.
    rewrite Pos2Nat.inj_xO.
    simpl.
    repeat rewrite pow_add.
    simpl.
    repeat rewrite Q2R_mult.
    repeat rewrite IHp.
    ring.
  }
  simpl.
  intros.
  ring.
Qed.

Lemma Q2R_pow q z:
  ~ q == 0%Q ->
  Q2R (q ^ z) = powerRZ (Q2R q) z.
Proof.
  intros.
  unfold powerRZ, Qpower.
  destruct z.
  {
    unfold Q2R. simpl. field.
  }
  {
    apply Q2R_Qpower_positive.
  }
  rewrite Q2R_inv.
  {
    f_equal.
    apply Q2R_Qpower_positive.
  }
  apply Qpower.Qpower_not_0_positive.
  assumption.
Qed.

Lemma F2BigQ2R beta f:
  BigQ2R (F2BigQ beta f) = F2R beta f.
Proof.
  destruct f; cbn -[BigQ.mul].
  unfold BigQ2R.
  rewrite BigQ.spec_mul.
  rewrite BigQ.spec_power.
  repeat rewrite to_Q_bigZ.
  repeat rewrite BigZ.spec_of_Z.
  rewrite Q2R_mult.
  rewrite Q2R_pow.
  {
    repeat rewrite Q2R_inject_Z.
    repeat rewrite <- Z2R_IZR.
    rewrite <- bpow_powerRZ.
    reflexivity.
  }
  replace 0%Q with (inject_Z 0) by reflexivity.
  rewrite inject_Z_injective.
  generalize (Zaux.radix_gt_0 beta).
  lia.
Qed.

Definition B2BigQ {prec emax} b := F2BigQ _ (@B2F prec emax b).

Lemma B2BigQ2R {prec emax} b:
  Binary.B2R prec emax b = BigQ2R (B2BigQ b).
Proof.
  unfold B2BigQ.
  rewrite F2BigQ2R.
  rewrite B2F_F2R_B2R.
  rewrite F2R_eq.
  reflexivity.
Qed.

Fixpoint blog (base: bigZ) (accu: nat) (z: bigZ) (fuel: nat) {struct fuel}: nat :=
  match fuel with
    | O => O
    | S fuel' =>
      if BigZ.eqb z BigZ.one
      then accu
      else
        let '(q, r) := BigZ.div_eucl z base in
        if BigZ.eqb r BigZ.zero
        then blog base (S accu) q fuel'
        else O
  end.

Definition to_power_2 {prec emax} (x: Binary.binary_float prec emax) :=
  let y := B2BigQ x in
  let '(q, r) := BigZ.div_eucl (Bnum y) (BigZ.Pos (Bden y)) in
  N.of_nat (blog (BigZ.of_Z 2) O q (Z.to_nat emax))
.

Definition to_inv_power_2 {prec emax} (x: Binary.binary_float prec emax) :=
  let y := BigQ.inv (B2BigQ x) in
  let '(q, r) := BigZ.div_eucl (Bnum y) (BigZ.Pos (Bden y)) in
  Pos.of_nat (blog (BigZ.of_Z 2) O q (Z.to_nat emax))
.

Definition fshift_mult (e'1 e'2: expr) :=
   let ty := type_lub (type_of_expr e'1) (type_of_expr e'2) in
        match fcval_nonrec e'1 with
          | Some c1' =>
            let c1 := cast ty _ c1' in
            let n := to_power_2 c1 in
            if binary_float_eqb c1 (B2 ty (Z.of_N n))
            then Unop (Exact1 (Shift n false)) (Unop (CastTo ty None) e'2)
            else
              let n := to_inv_power_2 c1 in
              if binary_float_eqb c1 (B2 ty (- Z.pos n))
              then Unop (Rounded1 (InvShift n false) None) (Unop (CastTo ty None) e'2)
              else Binop (Rounded2 MULT None) e'1 e'2
          | None =>
            match fcval_nonrec e'2 with
              | Some c2' =>
                let c2 := cast ty _ c2' in
                let n := to_power_2 c2 in
                if binary_float_eqb c2 (B2 ty (Z.of_N n))
                then Unop (Exact1 (Shift n true)) (Unop (CastTo ty None) e'1)
                else
                  let n := to_inv_power_2 c2 in
                  if binary_float_eqb c2 (B2 ty (- Z.pos n))
                  then Unop (Rounded1 (InvShift n true) None) (Unop (CastTo ty None) e'1)
                  else Binop (Rounded2 MULT None) e'1 e'2
              | None => Binop (Rounded2 MULT None) e'1 e'2
            end                  
        end.

Fixpoint fshift (e: FPLang.expr) {struct e}: FPLang.expr :=
  match e with
    | Binop b e1 e2 =>
      let e'1 := fshift e1 in
      let e'2 := fshift e2 in
      if binop_eqb b (Rounded2 MULT None)
      then fshift_mult e'1 e'2
      else Binop b e'1 e'2
    | Unop b e => Unop b (fshift e)
    | _ => e
  end.

Lemma fshift_type e:
  type_of_expr (fshift e) = type_of_expr e.
Proof.
  induction e; simpl; auto; unfold fshift_mult.
  {
    destruct (binop_eqb b (Rounded2 MULT None)) eqn:EQ.
    {
      apply binop_eqb_eq in EQ.
      subst.
      simpl.
      destruct (fcval_nonrec (fshift e1)).
      {
        revert IHe1 f. 
        generalize (fshift e1).
        intros until 1.
        rewrite IHe1.
        intros.
        simpl.
        match goal with
            |- type_of_expr (if ?v then _ else _) = _ =>
            destruct v
        end;
          simpl.
        {
          unfold Datatypes.id.
          congruence.
        }
        match goal with
            |- type_of_expr (if ?v then _ else _) = _ =>
            destruct v
        end; simpl;
        unfold Datatypes.id;
        congruence.
}
      destruct (fcval_nonrec (fshift e2)).
 {
        match goal with
            |- type_of_expr (if ?v then _ else _) = _ =>
            destruct v
        end; simpl.
        {
          unfold Datatypes.id.
          congruence.
        }
        match goal with
            |- type_of_expr (if ?v then _ else _) = _ =>
            destruct v
        end; simpl.
        {
        unfold Datatypes.id;
        congruence.
      }
        congruence.
      }
        simpl.
        congruence.
}
    simpl.
    congruence.
    }
    simpl.
    congruence.
Defined. 

Lemma fshift_correct' env e:
 binary_float_eqb (fval env (fshift e)) (fval env e) = true.
Proof.
  induction e; simpl; unfold fshift_mult.
  {
    apply binary_float_eqb_eq. reflexivity.
  }
  {
    apply binary_float_eqb_eq. reflexivity.
  }
  {
    destruct (binop_eqb b (Rounded2 MULT None)) eqn:ISMULT.
    {
      apply binop_eqb_eq in ISMULT.
      subst.
      destruct (fcval_nonrec (fshift e1)) eqn:E1.
      {
        generalize (fshift_type e1).
        destruct (fshift e1); try discriminate.
        simpl in E1.
        simpl in f.
        inversion E1; clear E1; subst.
        simpl in IHe1.
        simpl.
        intros.
        subst.
        apply binary_float_eqb_eq in IHe1.
        subst.
        match goal with
            |- binary_float_eqb (fval env (if ?b then _ else _)) _ = _ =>
            destruct b eqn:FEQ
        end;
          simpl.
        {
          unfold cast_lub_l.
          unfold cast_lub_r.
          revert IHe2.
          generalize (fval env (fshift e2)).
          revert FEQ.
          rewrite fshift_type.
          intros.
          apply binary_float_eqb_eq in IHe2.
          subst.
          apply binary_float_eqb_eq in FEQ.
          rewrite <- FEQ.
          apply binary_float_eqb_eq.
          reflexivity.
        }
        clear FEQ.
        match goal with
            |- binary_float_eqb (fval env (if ?b then _ else _)) _ = _ =>
            destruct b eqn:FEQ
        end;
          simpl.
        {
          unfold Datatypes.id.
          unfold cast_lub_l.
          unfold cast_lub_r.
          revert IHe2.
          generalize (fval env (fshift e2)).
          revert FEQ.
          rewrite fshift_type.
          intros.
          apply binary_float_eqb_eq in IHe2.
          subst.
          apply binary_float_eqb_eq in FEQ.
          rewrite <- FEQ.
          apply binary_float_eqb_eq.
          reflexivity.
        }
        clear FEQ.
        revert IHe2.
        generalize (fval env (fshift e2)).
        rewrite fshift_type.
        intros.
        apply binary_float_eqb_eq in IHe2.
        subst.
        apply binary_float_eqb_eq.
        reflexivity.
      }
      destruct (fcval_nonrec (fshift e2)) eqn:E2.
      {
        generalize (fshift_type e2).
        destruct (fshift e2); try discriminate.
        simpl in E2.
        simpl in f.
        inversion E2; clear E2; subst.
        simpl in IHe2.
        simpl.
        intros.
        subst.
        apply binary_float_eqb_eq in IHe2.
        subst.
        match goal with
            |- binary_float_eqb (fval env (if ?b then _ else _)) _ = _ =>
            destruct b eqn:FEQ
        end;
          simpl.
        {
          unfold cast_lub_l.
          unfold cast_lub_r.
          revert IHe1.
          generalize (fval env (fshift e1)).
          revert FEQ.
          rewrite fshift_type.
          intros.
          apply binary_float_eqb_eq in IHe1.
          subst.
          apply binary_float_eqb_eq in FEQ.
          rewrite <- FEQ.
          apply binary_float_eqb_eq.
          reflexivity.
        }
        clear FEQ.
        match goal with
            |- binary_float_eqb (fval env (if ?b then _ else _)) _ = _ =>
            destruct b eqn:FEQ
        end;
          simpl.
        {
          unfold cast_lub_l.
          unfold cast_lub_r.
          revert IHe1.
          generalize (fval env (fshift e1)).
          revert FEQ.
          rewrite fshift_type.
          intros.
          apply binary_float_eqb_eq in IHe1.
          subst.
          apply binary_float_eqb_eq in FEQ.
          rewrite <- FEQ.
          apply binary_float_eqb_eq.
          reflexivity.
        }
        clear FEQ.
        revert IHe1.
        generalize (fval env (fshift e1)).
        rewrite fshift_type.
        intros.
        apply binary_float_eqb_eq in IHe1.
        subst.
        apply binary_float_eqb_eq.
        reflexivity.
      }
      clear E1 E2.
      revert IHe1 IHe2.
      simpl.
      generalize (fval env (fshift e1)).
      generalize (fval env (fshift e2)).
      repeat rewrite fshift_type.
      intros.
      apply binary_float_eqb_eq in IHe1. subst.
      apply binary_float_eqb_eq in IHe2. subst.
      apply binary_float_eqb_eq.
      reflexivity.
    }
    clear ISMULT.
    revert IHe1 IHe2.
    simpl.
    generalize (fval env (fshift e1)).
    generalize (fval env (fshift e2)).
    repeat rewrite fshift_type.
    intros.
    apply binary_float_eqb_eq in IHe1. subst.
    apply binary_float_eqb_eq in IHe2. subst.
    apply binary_float_eqb_eq.
    reflexivity.
  }
  revert IHe.
  generalize (fval env (fshift e)).
  rewrite fshift_type.
  intros.
  apply binary_float_eqb_eq in IHe.
  subst.
  apply binary_float_eqb_eq.
  reflexivity.
Qed.

Lemma fshift_correct env e:
  fval env (fshift e) = eq_rect_r _ (fval env e) (fshift_type e).
Proof.
  apply binary_float_eqb_eq.
  apply binary_float_eqb_eq_strong.
  apply fshift_correct'.
Qed.

Definition to_power_2_pos {prec emax} (x: Binary.binary_float prec emax) :=
  let y := B2BigQ x in
  let '(q, r) := BigZ.div_eucl (Bnum y) (BigZ.Pos (Bden y)) in
  Pos.of_nat (blog (BigZ.of_Z 2) O q (Z.to_nat emax))
.

Fixpoint fshift_div (e: FPLang.expr) {struct e}: FPLang.expr :=
  match e with
    | Binop b e1 e2 =>
      let e'1 := fshift_div e1 in
      let e'2 := fshift_div e2 in
      if binop_eqb b (Rounded2 DIV None) then
      let ty := type_lub (type_of_expr e'1) (type_of_expr e'2) in
      match (fcval_nonrec e'2) with
            | Some c2' =>
                let c2 := cast ty _ c2' in
                match (Bexact_inverse (fprec ty) (femax ty) (fprec_gt_0 ty) (fprec_lt_femax ty) c2) with
                  | Some z' => 
                    let n1 := to_power_2_pos c2 in
                    if binary_float_eqb z' (B2 ty (Z.neg n1))
                    then Unop (Rounded1 (InvShift n1 true) None) (Unop (CastTo ty None) e'1)
                    else
                    let n2 := to_inv_power_2 c2 in
                    if binary_float_eqb z' (B2 ty (Z.pos n2))
                    then Unop (Exact1 (Shift (N.of_nat (Pos.to_nat n2)) true)) (Unop (CastTo ty None) e'1)
                    else Binop b e'1 e'2
                  | None => Binop b e'1 e'2
                end
             | None => Binop b e'1 e'2
         end
      else
        Binop b e'1 e'2
    | Unop b e => Unop b (fshift_div e)
    | _ => e
  end.


Lemma fshift_type_div e:
  type_of_expr (fshift_div e) = type_of_expr e.
Proof.
  induction e; simpl; auto; try congruence.
  destruct (binop_eqb b (Rounded2 DIV None)) eqn:EQ; [ | simpl; congruence].
  apply binop_eqb_eq in EQ.
  subst.
  simpl.
  destruct (fcval_nonrec (fshift_div e2)); [ | simpl; congruence].
  revert IHe2 f. 
  generalize (fshift_div e2).
  intros until 1.
  rewrite IHe2.
  intros.
  simpl.
  destruct (Bexact_inverse _ ); [ | simpl; congruence]. 
  repeat (match goal with
              |- type_of_expr (if ?v then _ else _) = _ => destruct v
          end;
          simpl; [ unfold Datatypes.id;  congruence | ]).
  congruence.
Defined. 

Local Lemma binary_float_equiv_refl : forall prec emax x, 
   @binary_float_equiv prec emax x x.
Proof. intros. destruct x; hnf; try reflexivity. repeat split; reflexivity. Qed.
Local Hint Resolve binary_float_equiv_refl : vcfloat.

Local Hint Resolve type_lub_left type_lub_right : vcfloat.

Local Hint Extern 2 (Binary.is_finite _ _ _ = true) => 
   match goal with EINV: Bexact_inverse _ _ _ _ _ = Some _ |- _ =>
             apply is_finite_strict_finite; 
         apply (Bexact_inverse_correct _ _ _ _ _ _ EINV)
   end : vcfloat.

Lemma cast_preserves_bf_equiv tfrom tto (b1 b2: Binary.binary_float (fprec tfrom) (femax tfrom)) :
  binary_float_equiv b1 b2 -> 
  binary_float_equiv (cast tto tfrom b1) (cast tto tfrom b2).
Proof.
intros.
destruct b1, b2; simpl; inversion H; clear H; subst; auto;
try solve [apply binary_float_eq_equiv; auto].
-
unfold cast; simpl.
destruct (type_eq_dec tfrom tto); auto.
unfold eq_rect.
destruct e1.
reflexivity.
reflexivity.
-
destruct H1; subst m0 e1.
unfold cast; simpl.
destruct (type_eq_dec tfrom tto); subst; auto.
unfold eq_rect.
simpl. split; auto.
apply binary_float_eq_equiv.
f_equal.
Qed.

Import Binary.

Lemma binary_float_equiv_BDIV ty (b1 b2 b3 b4: binary_float (fprec ty) (femax ty)):
binary_float_equiv b1 b2 ->
binary_float_equiv b3 b4 ->
binary_float_equiv (BDIV ty b1 b3) (BDIV ty b2 b4).
Proof.
intros.
destruct b1.
all : (destruct b3; destruct b4; try contradiction; try discriminate).
all :
match goal with 
  |- context [
binary_float_equiv (BDIV ?ty ?a ?b)
 _] =>
match a with 
| B754_nan _ _ _ _ _ => destruct b2; try contradiction; try discriminate;
    cbv [BDIV BINOP Bdiv build_nan binary_float_equiv]; try reflexivity
  | _ => apply binary_float_equiv_eq in H; try rewrite <- H;
  match b with 
  | B754_nan _ _ _ _ _ => 
      cbv [BDIV BINOP Bdiv build_nan binary_float_equiv]; try reflexivity
  | _ => apply binary_float_equiv_eq in H0; try rewrite <- H0;
          try apply binary_float_eq_equiv; try reflexivity
end
end
end.
Qed.

Lemma binary_float_equiv_BOP ty (b1 b2 b3 b4: binary_float (fprec ty) (femax ty)):
forall b: binop ,
binary_float_equiv b1 b2 ->
binary_float_equiv b3 b4 ->
binary_float_equiv (fop_of_binop b ty b1 b3) (fop_of_binop b ty b2 b4).
Proof.
intros.
destruct b1.
all :
match goal with 
  |- context [
binary_float_equiv (fop_of_binop ?bo ?ty ?a ?b)
 _] =>
match a with 
| B754_zero _ _ _ => 
apply binary_float_equiv_eq in H; try simpl; try reflexivity
| B754_infinity _ _ _ => 
apply binary_float_equiv_eq in H; try simpl; try reflexivity
| B754_finite _ _ _ _ _ _ => 
apply binary_float_equiv_eq in H; try simpl; try reflexivity
| _ => try simpl
end
end.
all :(
destruct b2; simpl in H; try contradiction; try discriminate;
destruct b3; destruct b4; try contradiction; try discriminate;
match goal with 
  |- context [ binary_float_equiv (fop_of_binop ?bo ?ty ?a ?b)  _] =>
match a with 
| B754_nan _ _ _ _ _  => try simpl
| _ => try (rewrite H); 
      match b with 
      | B754_nan _ _ _ _ _ => try simpl
      | _ => try (apply binary_float_equiv_eq in H);
             try (rewrite H);
             try (apply binary_float_equiv_eq in H0);
             try (rewrite H0);
             try (apply binary_float_eq_equiv); try reflexivity
      end
end
end
).

all: (
try (destruct b);
try( cbv [fop_of_binop]);
try destruct op;
try (cbv [fop_of_rounded_binop]);
try (cbv [fop_of_rounded_binop]);
try(
match goal with 
|- context [ binary_float_equiv ((if ?m then ?op1 else ?op2)  ?ty ?a ?b) _] =>
destruct m
end;
cbv [BPLUS BMINUS BDIV BMULT BINOP 
Bplus Bminus Bdiv Bmult build_nan binary_float_equiv]);
try (reflexivity)
).
Qed.

Lemma binary_float_equiv_UOP ty (b1 b2: binary_float (fprec ty) (femax ty)):
forall u: unop ,
binary_float_equiv b1 b2 ->
binary_float_equiv (fop_of_unop u ty b1) (fop_of_unop u ty b2).
Proof.
intros.
destruct b1.
all: (
match goal with |- context [binary_float_equiv 
(fop_of_unop ?u ?ty ?a) _]  =>
match a with 
| Binary.B754_nan _ _ _ _ _  => simpl 
| _ => try apply binary_float_equiv_eq in H; try rewrite  <-H; 
  try apply binary_float_eq_equiv; try reflexivity
end
end).
destruct b2; try discriminate; try contradiction.
try (destruct u).
all: (
try( cbv [fop_of_unop fop_of_exact_unop]);
try destruct op;
try destruct o;
try destruct ltr;
try (cbv [fop_of_rounded_unop]);
try (cbv [Bsqrt Binary.Bsqrt build_nan]);
try reflexivity
).
+ destruct (B2 ty (- Z.pos pow)) .
all: try (
 (cbv [ BMULT BINOP Bmult build_nan]);
 reflexivity).
+ destruct (B2 ty (Z.of_N pow)).
all: try (
 (cbv [ BMULT BINOP Bmult build_nan]);
 reflexivity).
+ apply cast_preserves_bf_equiv; auto.
Qed.


Local Hint Resolve cast_preserves_bf_equiv : vcfloat.
Local Hint Resolve binary_float_eq_equiv : vcfloat.
Local Ltac inv  H := inversion H; clear H; subst.

Lemma general_eqb_neq:
  forall {A} {f: A -> A -> bool} (H: forall x y, f x y = true <-> x=y),
    forall x y,  f x y = false <-> x<>y.
Proof.
intros.
rewrite <- H.
destruct (f x y); split; congruence.
Qed.

Local Ltac destruct_ifb H := 
    lazymatch type of H with
    | forall x y, ?f x y = true <-> x=y =>
         match goal with |- context [if f ?b ?c then _ else _] =>
                  let FEQ := fresh "FEQ" in 
                     destruct (f b c) eqn:FEQ; 
             [apply H in FEQ; rewrite FEQ in *
             | apply (general_eqb_neq H) in FEQ]
         end
    | _ => fail "argument of destruct_ifb must be a lemma of the form,  forall x y, ?f x y = true <-> x=y"
    end.

Local Lemma ifb_cases_lem: 
  forall {A} {f: A -> A -> bool} (H: forall x y, f x y = true <-> x=y),
  forall (x y: A) {B} (b c: B) (P: B -> Prop),
  (x=y -> P b) -> (x<>y -> P c) ->
  P (if f x y then b else c).
Proof.
intros.
destruct (f x y) eqn:?H.
apply H in H2; auto.
apply (general_eqb_neq H) in H2; auto.
Qed.

Local Lemma binary_float_eqb_lem1:
  forall prec emax b c {A} (y z: A) (P: A -> Prop) ,
    (b=c -> P y) -> P z ->
    P (if @binary_float_eqb prec emax prec emax b c then y else z).
Proof.
intros.
 destruct (binary_float_eqb b c) eqn:H1.
 apply H. apply binary_float_eqb_eq. auto. auto.
Qed.

Local Ltac binary_float_eqb_cases := 
  let H := fresh in 
  apply binary_float_eqb_lem1; [intro H; rewrite H in *; clear H | ].

Local Lemma Bmult_div_inverse_equiv ty:
  forall x y z: (Binary.binary_float (fprec ty) (femax ty)),
  Binary.is_finite _ _ y = true ->
  Binary.is_finite _ _ z = true ->
  Bexact_inverse (fprec ty) (femax ty) (fprec_gt_0 ty) (fprec_lt_femax ty) y = Some z -> 
  binary_float_equiv
  (Binary.Bmult _ _ _ (fprec_lt_femax ty) (mult_nan ty) Binary.mode_NE x z) 
  (Binary.Bdiv _ _ _ (fprec_lt_femax ty) (div_nan ty) Binary.mode_NE x y) .
Proof. intros. apply binary_float_equiv_sym; apply Bdiv_mult_inverse_equiv; auto. Qed.

Theorem Bmult_div_inverse_equiv2 ty:
  forall x1 x2 y z: (Binary.binary_float (fprec ty) (femax ty)),
  binary_float_equiv x1 x2 ->
  Binary.is_finite _ _ y = true ->
  Binary.is_finite _ _ z = true ->
  Bexact_inverse (fprec ty) (femax ty) (fprec_gt_0 ty) (fprec_lt_femax ty) y = Some z -> 
  binary_float_equiv
  (Binary.Bmult _ _ _ (fprec_lt_femax ty) (mult_nan ty) Binary.mode_NE x2 z)
  (Binary.Bdiv _ _ _ (fprec_lt_femax ty) (div_nan ty) Binary.mode_NE x1 y) .
Proof. intros. apply binary_float_equiv_sym; apply Bdiv_mult_inverse_equiv2; auto. Qed.

Lemma uncast_finite_strict:
  forall t t2 f, Binary.is_finite_strict (fprec t) (femax t) (cast t t2 f) = true ->
        Binary.is_finite_strict _ _ f = true.
Proof.
intros.
unfold cast in H.
destruct (type_eq_dec t2 t).
subst. 
destruct f; simpl in *; auto.
destruct f; simpl in *; auto.
Qed.

Lemma is_finite_strict_not_nan:
  forall prec emax f, Binary.is_finite_strict prec emax f = true -> Binary.is_nan prec emax f = false.
Proof.
intros.
destruct f; auto; discriminate.
Qed.

Lemma binary_float_equiv_nan:
  forall prec emax f1 f2,
  Binary.is_nan prec emax f1= true  ->
   Binary.is_nan prec emax f2 = true ->
    binary_float_equiv f1 f2.
Proof.
intros.
destruct f1; inv H.
destruct f2; inv H0.
apply I.
Qed.

Lemma binary_float_equiv_nan1:
  forall b prec emax f1 f2,
  Binary.is_nan prec emax f1= b  ->
    binary_float_equiv f1 f2 ->
   Binary.is_nan prec emax f2 = b.
Proof.
intros.
destruct b.
destruct f1; inv H.
destruct f2; inv H0.
reflexivity.
destruct f1; inv H;
destruct f2; inv H0;
reflexivity.
Qed.

Lemma binary_float_equiv_nan2:
  forall b prec emax f1 f2,
  Binary.is_nan prec emax f2= b  ->
    binary_float_equiv f1 f2 ->
   Binary.is_nan prec emax f1 = b.
Proof.
intros.
destruct b.
destruct f2; inv H.
destruct f1; inv H0.
reflexivity.
destruct f2; inv H;
destruct f1; inv H0;
reflexivity.
Qed.

Lemma Bmult_nan1:
  forall fprec emax H H0 H1 H2 f1 f2,
   Binary.is_nan fprec emax f1 = true -> Binary.is_nan _ _  (Binary.Bmult _ _ H H0 H1 H2 f1 f2) = true.
Proof.
intros.
destruct f1; try discriminate. reflexivity.
Qed.

Lemma Bmult_nan2:
  forall fprec emax H H0 H1 H2 f1 f2,
   Binary.is_nan fprec emax f2 = true -> Binary.is_nan _ _  (Binary.Bmult _ _ H H0 H1 H2 f1 f2) = true.
Proof.
intros. 
destruct f2; try discriminate.
destruct f1; reflexivity.
Qed.

Lemma Bdiv_nan1:
  forall fprec emax H H0 H1 H2 f1 f2,
   Binary.is_nan fprec emax f1 = true -> Binary.is_nan _ _  (Binary.Bdiv _ _ H H0 H1 H2 f1 f2) = true.
Proof.
intros.
destruct f1; try discriminate. reflexivity.
Qed.

Lemma Bdiv_nan2:
  forall fprec emax H H0 H1 H2 f1 f2,
   Binary.is_nan fprec emax f2 = true -> Binary.is_nan _ _  (Binary.Bdiv _ _ H H0 H1 H2 f1 f2) = true.
Proof.
intros. 
destruct f2; try discriminate.
destruct f1; reflexivity.
Qed.

Local Hint Resolve Bmult_nan1 Bmult_nan2 Bdiv_nan1 Bdiv_nan2 cast_is_nan : vcfloat.

Ltac unfold_fval := cbv [fop_of_unop fop_of_exact_unop fop_of_rounded_unop
                      fop_of_binop fop_of_rounded_binop cast_lub_l cast_lub_r
                      BDIV BMULT BINOP BPLUS BMINUS].

Definition binary_float_equiv_loose {prec1 emax1 prec2 emax2} 
(b1: binary_float prec1 emax1) (b2: binary_float prec2 emax2): Prop :=
  match b1, b2 with
    | B754_zero _ _ b1, B754_zero _ _ b2 => b1 = b2
    | B754_infinity _ _ b1, B754_infinity _ _ b2 =>  b1 = b2
    | B754_nan _ _ _ _ _, B754_nan _ _ _ _ _ => True
    | B754_finite _ _ b1 m1 e1 _, B754_finite _ _ b2 m2 e2 _ =>
      b1 = b2 /\  m1 = m2 /\ e1 = e2
    | _, _ => False
  end.

Lemma binary_float_equiv_loose_rect:
  forall t1 t2 (EQ: t1=t2) (b1: ftype t1) (b2: ftype t2),
  binary_float_equiv_loose b1 b2 <-> binary_float_equiv b1 (eq_rect_r ftype b2 EQ).
Proof.
intros.
subst t2.
apply iff_refl. 
Qed.

Lemma binary_float_equiv_loose_i:
  forall t (b1 b2: ftype t),
  binary_float_equiv b1 b2 -> binary_float_equiv_loose b1 b2.
Proof.
intros. auto.
Qed.

Lemma binary_float_equiv_loose_tighten:
  forall prec emax,
  @binary_float_equiv_loose prec emax prec emax = 
     @binary_float_equiv prec emax.
Proof.
intros. auto.
Qed.

Definition binary_float_equiv_loose_refl:
 forall prec emax b, @binary_float_equiv_loose prec emax prec emax b b.
Proof.
intros. destruct b; simpl; auto.
Qed.

Lemma binary_float_equiv_loose_eq prec emax (b1 b2: binary_float prec emax):
   binary_float_equiv_loose b1 b2 -> is_nan _ _ b1 =  false -> b1 = b2.
Proof.
intros. 
destruct b1, b2; try contradiction; try discriminate; simpl in H; subst; auto.
destruct H as [? [? ?]]; subst; auto.
f_equal; auto.
apply Classical_Prop.proof_irrelevance.
Qed.

Lemma binary_float_equiv_loose_nan:
  forall prec1 emax1 prec2 emax2 f1 f2,
  Binary.is_nan prec1 emax1 f1= true  ->
   Binary.is_nan prec2 emax2 f2 = true ->
    binary_float_equiv_loose f1 f2.
Proof.
intros.
destruct f1; inv H.
destruct f2; inv H0.
apply I.
Qed.

Lemma binary_float_equiv_loose_nan1:
  forall b prec1 emax1 prec2 emax2 f1 f2,
  Binary.is_nan prec1 emax1 f1= b  ->
    binary_float_equiv_loose f1 f2 ->
   Binary.is_nan prec2 emax2 f2 = b.
Proof.
intros.
destruct b.
destruct f1; inv H.
destruct f2; inv H0.
reflexivity.
destruct f1; inv H;
destruct f2; inv H0;
reflexivity.
Qed.


Ltac binary_float_equiv_tac :=
      repeat (first [ rewrite binary_float_equiv_loose_tighten in *
(*
                          | match goal with |- binary_float_equiv_loose ?x _ =>
                                      fail 100 "bingo" x
                            end
*)
                          | apply Bmult_div_inverse_equiv
                          | apply Bmult_div_inverse_equiv2
                          | apply cast_preserves_bf_equiv;
                               (assumption || apply binary_float_equiv_sym; assumption)
                          | apply binary_float_equiv_BDIV
                          | apply binary_float_equiv_BOP];
                   auto with vcfloat).

Ltac binary_float_equiv_tac2 env e1 e2 :=
         simpl; unfold cast_lub_l, cast_lub_r;
         rewrite ?binary_float_equiv_loose_tighten in *;
         repeat match goal with
                    | H: binary_float_equiv _ _ |- _ => revert H 
                    | H: binary_float_equiv_loose _ _ |- _ => revert H
                    end;
         generalize (fval env (fshift_div  e1));
         generalize (fval env (fshift_div  e2));
         rewrite !fshift_type_div;
         intros;
         binary_float_equiv_tac.

Lemma fshift_div_correct' env e:
 binary_float_equiv (fval env (fshift_div e)) (eq_rect_r ftype (fval env e) (fshift_type_div _)).
Proof.
apply binary_float_equiv_loose_rect.
induction e; cbn [fshift_div]; auto with vcfloat; unfold fval; fold (fval env);
try (set (x1 := fval env e1) in *; clearbody x1);
try (set (x2 := fval env e2) in *; clearbody x2);
try apply binary_float_equiv_loose_refl.
- (* binop case *)
 apply (ifb_cases_lem binop_eqb_eq); intros ?OP; subst;
               [ | binary_float_equiv_tac2 env e1 e2].
 destruct (fcval_nonrec (fshift_div e2)) eqn:E2;
               [ | binary_float_equiv_tac2 env e1 e2].
 generalize (fshift_type_div e2).
 destruct (fshift_div e2); try discriminate.
 simpl in *|-. inv E2.
 simpl in IHe2; cbn [type_of_expr]; intros; subst.
 destruct (Bexact_inverse _ ) eqn:EINV; [ | clear EINV];
               [ | binary_float_equiv_tac2 env e1 e2]. 
 assert (H := uncast_finite_strict _ _ _ 
                             (proj1 (Bexact_inverse_correct _ _ _ _ _ _ EINV))).
 destruct f; inversion H; clear H.
 apply binary_float_equiv_loose_eq in IHe2; [ subst x2 | reflexivity].
 rewrite positive_nat_N.
 destruct (fcval_nonrec (fshift_div e1)) eqn:E1.
 + generalize (fshift_type_div e1).
     destruct (fshift_div e1); try discriminate.
     simpl in f, E1, IHe1; inv E1.
     cbn [type_of_expr]; intros; subst ty.
     destruct (Binary.is_nan _ _ f) eqn:?NAN.
    * pose proof (binary_float_equiv_loose_nan1 true _ _ _ _ _ _ NAN IHe1).
       apply binary_float_equiv_loose_nan; repeat binary_float_eqb_cases;
       unfold fval; unfold_fval; auto with vcfloat.
    * apply binary_float_equiv_eq in IHe1; [ subst | assumption].
       repeat binary_float_eqb_cases; 
       binary_float_equiv_tac.
+ repeat binary_float_eqb_cases; [ .. | clear EINV];
    simpl; unfold cast_lub_l, cast_lub_r; 
    try revert EINV;
    revert IHe1;
    generalize (fval env (fshift_div e1));
    rewrite ?fshift_type_div;
    intros;
    cbn [type_of_expr type_of_unop];
    (destruct (Binary.is_nan _ _ f) eqn:?NAN;
       [pose proof (binary_float_equiv_loose_nan1 true _ _ _ _ _ _ NAN IHe1);
        unfold fval; fold (fval env); unfold_fval;
        apply binary_float_equiv_nan; auto with vcfloat
      | apply binary_float_equiv_eq in IHe1; [ subst | assumption ];
        binary_float_equiv_tac
     ]).
- (* unop case *)
 simpl.
revert IHe.
generalize (fval env (fshift_div e)).
rewrite fshift_type_div.
intros.
apply binary_float_equiv_UOP; apply IHe.
Qed.

Lemma fshift_div_correct env e:
  Binary.is_nan _ _ (fval env (fshift_div e)) = false -> 
  fval env (fshift_div e) = eq_rect_r _ (fval env e) (fshift_type_div e).
Proof.
  intros.
  apply binary_float_equiv_eq. 
  - apply fshift_div_correct'.
  - apply H. 
Qed.

Definition is_zero_expr (env: forall ty, V -> ftype ty) (e: FPLang.expr)
 : bool :=  
match (fval env e) with
| Binary.B754_zero _ _ b1 => true
| _ => false
end.

(* Erasure of rounding annotations *)

Fixpoint erase (e: FPLang.expr (V := V)) {struct e}: FPLang.expr :=
  match e with
    | Binop (Rounded2 u k) e1 e2 => Binop (Rounded2 u None) (erase e1) (erase e2)
    | Binop SterbenzMinus e1 e2 => Binop (Rounded2 MINUS None) (erase e1) (erase e2)
    | Binop (PlusZero minus_ _) e1 e2 => Binop (Rounded2 (if minus_ then MINUS else PLUS) None) (erase e1) (erase e2)
    | Unop (Rounded1 u k) e => Unop (Rounded1 u None) (erase e)
    | Unop (CastTo u _) e => Unop (CastTo u None) (erase e)
    | Unop u e => Unop u (erase e)
    | _ => e
  end.

Lemma erase_type e: type_of_expr (erase e) = type_of_expr e.
Proof.
  induction e; simpl; auto.
  {
    destruct b; simpl; intuition congruence.
  }
  destruct u; simpl; intuition congruence.
Defined. (* required because of eq_rect_r *)

Lemma erase_correct' env e:
 binary_float_eqb (fval env (erase e)) (fval env e) = true.
Proof.
  induction e; simpl.
  {
    apply binary_float_eqb_eq; reflexivity.
  }
  {
    apply binary_float_eqb_eq; reflexivity.
  }
  {
    unfold cast_lub_r.
    unfold cast_lub_l.
    revert IHe1.
    revert IHe2.
    generalize (fval env e1).
    generalize (fval env e2).
    destruct b; simpl; unfold cast_lub_r, cast_lub_l;
      generalize (fval env (erase e1));
      generalize (fval env (erase e2));
      repeat rewrite erase_type;
      intros until 2;
      apply binary_float_eqb_eq in IHe1; subst;
      apply binary_float_eqb_eq in IHe2; subst;
      apply binary_float_eqb_eq;
      try reflexivity.
    destruct minus; reflexivity.
  }
  revert IHe.
  generalize (fval env e).
  destruct u; simpl;
  generalize (fval env (erase e));
  repeat rewrite erase_type;
  intros until 1;
  apply binary_float_eqb_eq in IHe; subst;
  apply binary_float_eqb_eq;
  reflexivity.
Qed.

Lemma erase_correct env e:
  fval env (erase e) = eq_rect_r _ (fval env e) (erase_type e).
Proof.
  apply binary_float_eqb_eq.
  apply binary_float_eqb_eq_strong.
  apply erase_correct'.
Qed.

End WITHVARS.
