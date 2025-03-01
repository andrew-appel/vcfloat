(** Automate.v:  proof automation for "ftype" usage-style of VCFloat.
 Copyright (C) 2021-2022 Andrew W. Appel.
*)

From vcfloat Require Import FPLang FPLangOpt RAux Rounding Reify Float_notations.
Require Import Interval.Tactic.
Import Binary.
Import List ListNotations.
Set Bullet Behavior "Strict Subproofs".

Open Scope R_scope.

Definition generic_nan (prec emax : Z) : 
      nan_pl prec 1 = true ->
       binary_float prec emax  := 
       B754_nan prec emax false 1.

Definition generic_nan64 := 
  generic_nan (fprec Tdouble) (femax Tdouble) (eq_refl _).

Ltac float_nearest mode r :=
 match r with
  | Rmult (IZR ?a) (Rinv ?b) => let x := constr:(Rdiv (IZR a) (IZR b)) in float_nearest x
  | Rdiv (IZR ?a) (IZR ?b) =>
   let f := constr:( Bdiv_full  (fprec Tdouble) (femax Tdouble) (eq_refl _) (eq_refl _) 
                                  (fun _ _ => exist _ generic_nan64 (eq_refl _))
                            mode (Zconst _ a) (Zconst _ b)) in
   let f := eval vm_compute in f in
   match f with F754_finite ?s ?m ?e =>
          let g := constr:(b64_B754_finite s m e (eq_refl true))
     in g
   end
 end.

Definition FT2R {t: type} : ftype t -> R := B2R (fprec t) (femax t).

Ltac compute_B2R :=
 repeat (
 match goal with |- context [B2R ?a ?b ?c] =>
   lazymatch c with
   | b64_B754_finite _ _ _ _ => idtac
   | b64_B754_zero _ => idtac 
   | b32_B754_finite _ _ _ _ => idtac
   | b32_B754_zero _ => idtac 
  end;
 let x := constr:(B2R a b c) in
 let y := eval cbv beta iota zeta delta [
               FT2R b64_B754_finite B2R Defs.F2R Defs.Fnum Defs.Fexp
                 SpecFloat.cond_Zopp bpow radix2 radix_val
                 Z.pow_pos Pos.iter Z.mul Pos.mul] in x
 in lazymatch y with
    | Rmult ?u (Rinv ?v) => let z := constr:(Rdiv u v) in change x with z
    | _ => change x with y
    end
 end).

Record varinfo := {var_type: type; var_name: ident; var_lobound: R; var_hibound: R}.
Definition boundsmap := Maps.PTree.t varinfo.
Definition valmap := Maps.PTree.t (sigT ftype).

Definition ftype_of_val (v: sigT ftype) : type := projT1 v.
Definition fval_of_val (v: sigT ftype): ftype (ftype_of_val v) := projT2 v.

Definition bogus_type : type.
 refine {| fprecp := 2; femax := 3 |}.
 constructor. simpl. auto.
Defined.

Module SET_ASIDE.

(* This stuff might be useful later *)
Definition bogus_val : ftype bogus_type := B754_zero _ _ false.

Definition mk_env (bm: boundsmap) (vm: valmap) (ty: type) (i: ident) : ftype ty.
destruct (Maps.PTree.get i bm) as [[t i' lo hi]|] eqn:?H.
destruct (type_eq_dec ty t).
subst.
destruct (Maps.PTree.get i vm) as [v |].
destruct (type_eq_dec (ftype_of_val v) t).
subst.
apply (fval_of_val v).
apply (B754_zero _ _ true).
apply (B754_zero _ _ true).
apply (B754_zero _ _ true).
apply (B754_zero _ _ true).
Defined.

Definition list_to_bound_env 
  (bindings: list  (ident * varinfo)) 
  (bindings2: list  (ident * sigT ftype)) :
  @environ ident :=
 let bm := Maps.PTree_Properties.of_list bindings in
 let vm := Maps.PTree_Properties.of_list bindings2 in 
 mk_env bm vm.

End SET_ASIDE.

Definition boundsmap_denote (bm: boundsmap) (vm: valmap) : Prop :=
   forall i, 
   match Maps.PTree.get i bm, Maps.PTree.get i vm with
   | Some {|var_type:=t; var_name:=i'; var_lobound:=lo; var_hibound:=hi|}, Some v => 
              i=i' /\ t = projT1 v /\ 
              is_finite (fprec _) (femax _) (projT2 v) = true /\ lo <= FT2R (projT2 v) <= hi
   | None, None => True
   | _, _ => False
   end.

Definition boundsmap_denote_pred (vm: valmap) (ib: ident*varinfo) := 
 match ib with
                  (i, {|var_type:=t; var_name:=i'; var_lobound:=lo; var_hibound:=hi|}) =>
                  exists v,
                    i=i' /\
                    Maps.PTree.get i vm = Some v /\
              is_finite (fprec _) (femax _) (projT2 v) = true /\ lo <= FT2R (projT2 v) <= hi
                   end.

Lemma boundsmap_denote_e:
  forall bm vm, boundsmap_denote bm vm -> 
 list_forall (boundsmap_denote_pred vm) (Maps.PTree.elements bm).
Proof.
intros.
red in H.
unfold boundsmap_denote_pred.
apply list_forall_spec.
intros [i [t i' lo hi]] ?.
apply Maps.PTree.elements_complete in H0.
specialize (H i). rewrite H0 in H.
destruct (Maps.PTree.get i vm) as [ v | ]; try contradiction.
destruct H as [? [? [? ?]]].
subst.
exists v. auto. 
Qed.

Ltac compute_PTree x :=
 match x with
 | Maps.PTree.Nodes ?y => let y' := compute_PTree y in constr:(Maps.PTree.Nodes y')
 | Maps.PTree.Empty => constr:(x)
 | Maps.PTree.Node001 ?y => let y' := compute_PTree y in constr:(Maps.PTree.Node001 y')
 | Maps.PTree.Node010 _ => constr:(x)
 | Maps.PTree.Node011 ?a ?y => let y' := compute_PTree y in constr:(Maps.PTree.Node011 a y')
 | Maps.PTree.Node100 ?y => let y' := compute_PTree y in constr:(Maps.PTree.Node100 y')
 | Maps.PTree.Node101 ?y ?z => let y' := compute_PTree y in
                                                 let z' := compute_PTree z in
                                                    constr:(Maps.PTree.Node101 y' z')
 | Maps.PTree.Node110 ?y ?a => let y' := compute_PTree y in constr:(Maps.PTree.Node110 y' a)
 | Maps.PTree.Node111 ?y ?a ?z => let y' := compute_PTree y in
                                                 let z' := compute_PTree z in
                                                    constr:(Maps.PTree.Node111 y' a z')
 | _ => let y := eval hnf in x in compute_PTree y
 end.

Definition boundsmap_of_list (vl: list varinfo) : boundsmap :=
  fold_left (fun m v => Maps.PTree.set (var_name v) v m) vl (Maps.PTree.empty _).

Definition valmap_of_list (vl: list (ident * sigT ftype)) : valmap :=
  fold_left (fun m iv => let '(i,v) := iv in Maps.PTree.set i v m) vl (Maps.PTree.empty _).

Instance identVars: VarType ident := Build_VarType ident Pos.eqb Pos.eqb_eq.

Definition shiftmap := Maps.PMap.t (type * rounding_knowledge').

Instance shifts_MAP: Map nat (type * rounding_knowledge') shiftmap :=
   compcert_map _ _ map_nat.

Definition env_ (tenv: valmap) ty (v: ident): ftype ty :=
  match Maps.PTree.get v tenv with Some (existT _ t x) =>
      match type_eq_dec ty t with
        | left K => eq_rect_r _ x K
        | _ => B754_zero _ _ true
      end
    | _ => B754_zero _ _ true
  end.

Lemma finite_env (bmap: boundsmap) (vmap: valmap):
      boundsmap_denote bmap vmap ->
forall ty i, is_finite (fprec ty) (femax ty) ((env_ vmap) ty i) = true.
Proof. 
intros.
 unfold  env_.
 specialize (H i).
 destruct (Maps.PTree.get i bmap) as [[t i' lo hi]|],
    (Maps.PTree.get i vmap) as [[t' v]|]; auto.
 destruct H as [? [? [??]]].
simpl in H0, H1, H2.
subst i' t'.
destruct (type_eq_dec ty t); auto.
subst ty.
auto.
Qed.

Ltac unfold_fval :=
  cbv beta iota zeta delta [
      fop_of_binop fop_of_rounded_binop cast_lub_l cast_lub_r
      fop_of_unop fop_of_rounded_unop fop_of_exact_unop
      option_pair_of_options];
   try change (type_lub _ _) with Tsingle;
   try change (type_lub _ _) with Tdouble;
   repeat change (type_lub ?x ?y) with x;
   repeat change (type_lub ?x ?y) with y;
   repeat match goal with
  | |- context [binop_eqb ?a ?b] =>
    let u := constr:(binop_eqb a b) in
    let u := eval compute in u in
    change (binop_eqb a b) with u; cbv iota
  | |- context [binary_float_eqb ?a ?b] =>
    let u := constr:(binary_float_eqb a b) in
    let u := eval compute in u in
    change (binary_float_eqb a b) with u; cbv iota
  | |- context [to_inv_power_2 ?a] =>
    let u := constr:(to_inv_power_2 a) in
    let u := eval compute in u in
    change (to_inv_power_2 a) with u; cbv iota
  end;
   cbv beta iota zeta;
   repeat change (cast ?a _ ?x) with x.

Definition rndval_with_cond_result1 {NANS: Nans} env e (r: @rexpr ident) (s: Maps.PMap.t (type * rounding_knowledge')) :=
    exists errors,
        (errors_bounded s errors)
        /\
        let fv := fval env e in
        is_finite _ _ fv = true
        /\
        reval r env errors = B2R _ _ fv.

Lemma boundsmap_denote_pred_e:
  forall vm i' t i lo hi,
    boundsmap_denote_pred vm (i',
     {| var_type := t; var_name := i; var_lobound := lo; var_hibound := hi |}) ->
    match Maps.PTree.get i vm with
     | Some (existT _ t v) => (lo <= @FT2R t v <= hi)%R                         
     | None => False
    end.
Proof.
intros.
destruct H.
destruct x.
destruct H as [? [? [??]]].
subst.
simpl in *. rewrite H0. auto.
Qed.

Definition eval_cond' s (c: cond) (env: environ) : Prop :=
  @eval_cond2 ident _ shifts_MAP _ (compcert_map nat R map_nat) env s c.

Definition rndval_with_cond2 (e: expr) : rexpr * shiftmap * list (environ -> Prop) :=
 let '((r,(si,s)),p) := rndval_with_cond' 0 empty_shiftmap e
  in (r, s, map (eval_cond' s) p).

Lemma rndval_with_cond_correct2 {NANS: Nans}:
 forall 
  (e: expr) (VALID: expr_valid e = true)
  (bm: boundsmap) (vm: valmap),
  boundsmap_denote bm vm ->
  let '(r,s,p) := rndval_with_cond2 e in 
  Forall (fun c => c (env_ vm)) p ->
  exists errors,
      (errors_bounded s errors) /\
        let fv := fval (env_ vm) e in
        is_finite _ _ fv = true
        /\ reval r (env_ vm) errors = B2R _ _ fv.
Proof.
intros.
assert (env_all_finite (env_ vm)) by (intros ? ? ; eapply finite_env; eauto).
destruct ( rndval_with_cond e) as [[r s] p] eqn:?H.
pose proof (rndval_with_cond_correct _ H0 _ VALID _ _ _ H1).
unfold rndval_with_cond in H1.
unfold rndval_with_cond2.
destruct (rndval_with_cond' 0 empty_shiftmap e) as [[? [? ?]] ?].
inversion H1; clear H1; subst.
intros.
destruct H2 as [errors [? [? ?]]].
-
induction l. constructor.
inversion H1; clear H1; subst.
apply Forall_cons; auto.
unfold eval_cond. unfold eval_cond' in H4.
apply eval_cond2_correct in H4; auto.
-
exists errors.
auto.
Qed.

Lemma invert_quad:
  forall (a a': @rexpr ident) (b b': nat) (c c': shiftmap) (d d': list (@cond ident)) (G: Prop),
  (a=a' -> b=b' -> c=c' -> d=d' -> G) ->
  (a,(b,c),d) = (a',(b',c'),d') -> G.
Proof.
intros.
inversion H0; auto.
Qed.

Ltac invert_rndval_with_cond' :=
 match goal with
 | |- rndval_with_cond' 0 empty_shiftmap ?e = (_, (_,_), _) -> ?M' =>
    let M := fresh "M" in set (M:=M');
   cbv beta iota zeta delta [rndval_with_cond' rnd_of_binop_with_cond
          rnd_of_unop_with_cond is_div
          Rbinop_of_rounded_binop Runop_of_exact_unop Runop_of_rounded_unop
          type_of_expr make_rounding round_knowl_denote];
   try change (type_lub _ _) with Tsingle;
   try change (type_lub _ _) with Tdouble;
   repeat change (type_lub ?x ?y) with x;
   repeat change (type_lub ?x ?y) with y;
   repeat change (binop_eqb _ _) with true;
   repeat change (binop_eqb _ _) with false;
 cbv beta iota zeta delta [rounding_cond_ast no_overflow app];
 match goal with |- (?r1,(_, ?s1), ?l1) = _ -> _ =>
    let r' := fresh "r" in let s' := fresh "s" in let l' := fresh "l" in 
    set (r' := r1); set (s' := s1); set (l' := l1);
    let H1 := fresh "H" in 
     apply invert_quad; intros; subst;

     cbv beta iota zeta delta [mset shifts_MAP empty_shiftmap mempty
            compcert_map Maps.PMap.set Maps.PMap.init
            Maps.PTree.empty Maps.PTree.set Maps.PTree.set' 
              Maps.PTree.set0 Pos.of_succ_nat Pos.succ
            index_of_tr map_nat fst snd] in s';

     subst r'; subst s'; subst l'
  end;
  subst M
 | _ => fail "invert_rndval_with_cond' at inappropriate goal"
 end.

Ltac process_boundsmap_denote := 
 lazymatch goal with
 | H: boundsmap_denote _ _ |- _ =>
  apply boundsmap_denote_e in H;
  simpl Maps.PTree.elements in H;
  unfold list_forall in H;
repeat lazymatch type of H with 
 | _ /\ _ => let B := fresh "BOUND" in destruct H as [B H];
    apply boundsmap_denote_pred_e in B; simpl in B
 | True => clear H
 | _ => let B := fresh "BOUND" in rename H into B;
    apply boundsmap_denote_pred_e in B; simpl in B
 end
end.

Ltac process_eval_cond' :=
 lazymatch goal with 
 | |- eval_cond' _ _ _ => idtac
 | _ => fail 1 "inappropriate goal for process_eval_cond'"
 end;
    hnf;
  repeat 
   (let H := fresh in intros ?u H;
    cbv beta iota zeta delta [
    mget shifts_MAP compcert_map
    Maps.PMap.get Maps.PTree.get Maps.PTree.get'
      Pos.of_succ_nat Pos.succ
      index_of_tr map_nat fst snd] in H;
    unfold error_bound in H;
    simpl in H;
    unfold Z.pow_pos in H;
    simpl Pos.iter in H);

   cbv beta iota zeta delta [
            mset shifts_MAP empty_shiftmap mempty
            compcert_map Maps.PMap.set Maps.PMap.init
            Maps.PTree.empty Maps.PTree.set Maps.PTree.set' 
              Maps.PTree.set0 Pos.of_succ_nat Pos.succ
            index_of_tr map_nat fst snd];

 cbv beta iota zeta delta [reval
     Prog.binary Prog.unary Prog.real_operations
   Tree.binary_real Tree.unary_real
  ];

  cbv beta iota zeta delta [
    mget shifts_MAP compcert_map
    Maps.PMap.get Maps.PTree.get Maps.PTree.get'
      Pos.of_succ_nat Pos.succ
      index_of_tr map_nat fst snd];

 repeat 
   match goal with |- context [env_ ?m ?t ?i ] =>
     let j := fresh "j" in set (j := env_ m t i); hnf in j; subst j
   end;
 
  change (B2R (fprec ?t) _ ?x) with (@FT2R t x);
  simpl F2R.

Definition prove_rndval' {NANS: Nans} bm vm e :=
 boundsmap_denote bm vm ->
  let
   '(r, s, _) := rndval_with_cond2 (fshift_div (fshift (fcval e))) in
    rndval_with_cond_result1 (env_ vm) e r s.

Definition prove_rndval {NANS: Nans} bm vm e :=
  {rs | fst (rndval_with_cond2 (fshift_div (fshift (fcval e)))) = rs /\  
         (boundsmap_denote bm vm ->
          let '(r,s) := rs in rndval_with_cond_result1 (env_ vm) e r s)}.

Lemma prove_rndval'_e {NANS: Nans}:
  forall bm vm e, prove_rndval' bm vm e -> prove_rndval bm vm e.
Proof.
unfold prove_rndval', prove_rndval; intros.
destruct (rndval_with_cond2 _) as [[r s] p]; simpl in *.
exists (r,s); auto.
Qed.

Lemma prove_rndval'_i1 {NANS: Nans} bm vm e :
 (boundsmap_denote bm vm ->
  is_finite (fprec (type_of_expr (fshift_div (fcval e))))
       (femax (type_of_expr (fshift_div (fcval e))))
       (fval (env_ vm) (fshift_div (fcval e))) = true ->
  let
   '(r, s, _) := rndval_with_cond2 (fshift_div (fcval e)) in
    rndval_with_cond_result1 (env_ vm) e r s)
 -> prove_rndval' bm vm e.
Proof.
intros.
red; intros.
specialize (H H0).
destruct (rndval_with_cond2 _) as [[? ?] ?].
red; intros.
Abort.

Ltac process_conds :=
 (apply Forall_cons; [process_eval_cond' | process_conds ]) || apply Forall_nil.

Lemma fshift_div_fshift_fcval_type {NANS: Nans} {V : Type}:
      forall e : expr, @type_of_expr V (fshift_div (fshift (fcval e))) = @type_of_expr V e.
Proof.
intros.
eapply eq_trans.
apply fshift_type_div.
eapply eq_trans.
apply fshift_type.
apply fcval_type.
Defined.

Lemma binary_float_equiv_loose_sym prec1 emax1 prec2 emax2
       (b1: binary_float prec1 emax1) (b2: binary_float prec2 emax2):
     binary_float_equiv_loose b1 b2 -> binary_float_equiv_loose b2 b1.
Proof.
intros.
destruct b1; destruct b2; simpl; auto. 
destruct H as (A & B & C); subst; auto. Qed.


Lemma binary_float_equiv_eq_rect_r:
  forall t t1 t2 (v1: ftype t1) (v2: ftype t2) EQ1 EQ2,
  binary_float_equiv_loose v1 v2 ->
  @binary_float_equiv (fprec t) (femax t) (eq_rect_r ftype v1 EQ1) (eq_rect_r ftype v2 EQ2) .
Proof.
intros.
subst.
unfold eq_rect_r, eq_rect; simpl.
auto.
Qed.

Lemma fshift_div_fshift_fcval_correct {NANS: Nans} {V: Type}:
  forall (env : forall ty : type, V -> ftype ty) (e : expr),
  binary_float_equiv (fval env (fshift_div (fshift (fcval e)))) 
               (eq_rect_r ftype (fval env e) (fshift_div_fshift_fcval_type e)).
Proof.
intros.
eapply binary_float_equiv_trans.
apply fshift_div_correct'.
apply binary_float_equiv_eq_rect_r.
rewrite fshift_correct.
rewrite fcval_correct.
apply binary_float_equiv_loose_sym.
apply  (binary_float_equiv_loose_rect _ _ 
       (eq_sym (eq_trans (fshift_type _) (fcval_type _))) (fval env e)).
unfold eq_rect_r.
rewrite !rew_compose.
rewrite !eq_trans_sym_distr, !eq_sym_involutive.
rewrite (eq_trans_assoc  (eq_sym (fshift_type (fcval e)))).
rewrite eq_trans_sym_inv_l, eq_trans_refl_l.
rewrite eq_trans_sym_inv_l.
simpl.
apply binary_float_equiv_refl.
Qed.

Lemma fshift_fcval_type{NANS: Nans} {V : Type}:
      forall e : expr, @type_of_expr V (fshift (fcval e)) = @type_of_expr V e.
Proof.
intros.
eapply eq_trans.
apply fshift_type. apply fcval_type.
Defined.

Lemma fshift_fcval_correct {NANS: Nans} {V: Type}:
  forall (env : forall ty : type, V -> ftype ty) (e : expr),
  fval env (fshift (fcval e)) = eq_rect_r ftype (fval env e) (fshift_fcval_type e).
Proof.
intros.
rewrite fshift_correct.
rewrite fcval_correct.
unfold eq_rect_r.
rewrite <- eq_trans_rew_distr.
f_equal.
rewrite <- eq_trans_sym_distr.
f_equal.
Qed.


Lemma binary_float_equiv_loose_iff:
  forall t1 t2 (EQ: t1=t2) (b1: ftype t1) (b2: ftype t2),
  binary_float_equiv_loose b1 b2 <-> binary_float_equiv b1 (eq_rect_r ftype b2 EQ).
Proof.
intros.
subst t2.
apply iff_refl.
Qed.

Lemma rndval_with_cond_result1_fvals_eq {NANS: Nans}:
  forall env e1 e2 EQ r s,
  binary_float_equiv (fval env e1) (eq_rect_r ftype (fval env e2) EQ) -> 
  rndval_with_cond_result1 env e1 r s ->
  rndval_with_cond_result1 env e2 r s.
Proof.
intros.
rewrite <- binary_float_equiv_loose_iff in H.
destruct H0 as [errors [? [? ?]]].
exists errors. split; auto.
assert (FIN: is_finite (fprec (type_of_expr e2)) (femax (type_of_expr e2)) (fval env e2) =
true). {
  rewrite <- H1; clear H1.
  clear - H.
  destruct (fval env e1), (fval env e2); try reflexivity; try contradiction.
}
split; auto.
rewrite H2.
clear - H1 FIN H EQ.
destruct (fval env e1), (fval env e2); try discriminate; clear H1 FIN;
simpl in H; decompose [and] H; subst;
 try contradiction;
simpl; auto.
Qed.

Lemma rndval_with_cond_correct2_opt {NANS: Nans}:
      forall (e0 e1 e: expr) (EQ1: e1 = e) EQt,
       expr_valid e = true ->
       forall (bm : boundsmap) (vm : valmap),
       boundsmap_denote bm vm ->
       @binary_float_equiv (fprec (type_of_expr e1)) (femax (type_of_expr e1))
            (fval (env_ vm) e1)
            (eq_rect_r ftype (fval (env_ vm) e0) EQt) ->
       let  '(r, s, p) := rndval_with_cond2 e in
        Forall (fun c : (forall ty : type, positive -> ftype ty) -> Prop => c (env_ vm)) p ->
        rndval_with_cond_result1 (env_ vm) e0 r s.
Proof.
intros.
subst e1.
pose proof (rndval_with_cond_correct2 e H _ _ H0).
destruct (rndval_with_cond2 e) as [[? ?] ?].
intro.
specialize (H2 H3).
change (rndval_with_cond_result1 (env_ vm) e r s) in H2.
eapply rndval_with_cond_result1_fvals_eq.
 eassumption.
assumption.
Qed.

Ltac prove_rndval := 
 (* if necessary, convert goal into a prove_rndval'   goal*)
 lazymatch goal with
 | |- prove_rndval _ _ _ => apply prove_rndval'_e
 | |- _ => idtac
 end;

 (* introduce the boundsmap_denote *)
 lazymatch goal with |- @prove_rndval' ?NANS ?bm ?vm ?ee =>
  let e0 := fresh "e0" in set (e0:=ee);
  change Reify.ident with ident in e0;
  let H := fresh in intro H;
  let EQ := fresh "EQ"  in let EQ0 := fresh "EQ" in
  let e1 := fresh "e1" in  let e := fresh "e" in 

 (* e0 is the original expression.  e1 is the optimization functions applied to e0, not yet reduced.
    e is the reduced-to-normal form version of e1, that is, the optimized expression. *)

  (* calculate appropriate equivalences between e0, e1, e *)
  pose (e1 := @fshift_div ident NANS (@fshift ident NANS (@fcval ident NANS e0)));
  assert (EQ: (@fshift_div ident NANS (@fshift ident NANS (@fcval ident NANS e0)) = e1 /\
           binary_float_equiv (fval (env_ vm) e1) (fval (env_ vm) e0)))
    by (split; [apply eq_refl | 
                   eapply binary_float_equiv_trans; [ apply fshift_div_fshift_fcval_correct | ];
                   apply binary_float_equiv_sym;
                   apply binary_float_equiv_loose_rect; 
                   apply binary_float_equiv_loose_refl]);

  (* Now compute the fcval optimization *)
  revert EQ;
   pattern e1 at 1;
  let M := fresh "M" in set (M := fun _ => _);

  cbv beta iota zeta delta - [M fshift_div fshift Bmult Bplus Bminus Bdiv 
                                       plus_nan mult_nan div_nan abs_nan opp_nan sqrt_nan];
 fold Tsingle; fold Tdouble;
  compute_binary_floats;

    (* Now compute the remaining optimizations  (fshift, fshift_div) *)
  cbv beta iota zeta delta - [M Bmult Bplus Bminus Bdiv 
                                       plus_nan mult_nan div_nan abs_nan opp_nan sqrt_nan];
 fold Tsingle; fold Tdouble;

 (* Now clean up after optimizing *)
 match goal with |- M ?ee => set (e:=ee) end;
 subst M; cbv beta;
 intros [EQ EQ0];
 rewrite EQ;

 (* Now apply the main lemma *)
 apply (rndval_with_cond_correct2_opt e0 e1 e EQ (eq_refl _) (eq_refl _) _ _ H EQ0);
 clear EQ EQ0 e e1 e0;

  (* What's left is a Forall of all the conds.  Next, clean them up a bit. *)
  change (type_of_expr _) with Tsingle;
  change (type_of_expr _) with Tdouble;
  cbv beta iota zeta delta [
            mset shifts_MAP empty_shiftmap mempty
            compcert_map Maps.PMap.set Maps.PMap.init
            Maps.PTree.empty Maps.PTree.set Maps.PTree.set' 
              Maps.PTree.set0 Pos.of_succ_nat Pos.succ
            index_of_tr map_nat fst snd

          rndval_with_cond' rnd_of_binop_with_cond
          rnd_of_unop_with_cond is_div
          Rbinop_of_rounded_binop Runop_of_exact_unop Runop_of_rounded_unop
          type_of_expr make_rounding round_knowl_denote
         rounding_cond_ast no_overflow app];
 
  (* now process the boundsmap above the line, and the conds below the line *)
  process_boundsmap_denote;
  process_conds

 end.

Lemma errors_bounded_e:
  forall errors t0 k0 m, errors_bounded (t0, k0, m) errors ->
   Forall (fun it => let '(i,(ty,k)) := it in 
                   Rle (Rabs (errors (pred (Pos.to_nat i)))) (error_bound ty k))
      (Maps.PTree.elements m).
Proof.
intros.
red in H.
apply Forall_forall.
intros.
destruct x as [i [ty k]].
apply Maps.PTree.elements_complete in H0.
apply H.
unfold mget; simpl.
unfold Maps.PMap.get.
simpl.
replace (Pos.of_succ_nat (Init.Nat.pred (Pos.to_nat i))) with i; auto.
rewrite H0; auto.
clear.
rewrite (SuccNat2Pos.inv _ i); auto.
rewrite Nat.succ_pred; auto.
lia.
Qed.

Definition rndval_without_cond (e: expr) : rexpr * shiftmap :=
 let '(r,s,p) := rndval_with_cond2 e in (r,s).

Lemma rndval_with_cond_result1_e {NANS: Nans}:
  forall vm e r s, 
   rndval_with_cond_result1 (env_ vm) e r s ->
  let '(_, m) := s in 
   exists errors: nat -> R,
     Forall (fun it => let '(i,(ty,k)) := it in 
                   Rle (Rabs (errors (pred (Pos.to_nat i)))) (error_bound ty k))
      (Maps.PTree.elements m) /\
  (let fv := fval (env_ vm) e in
   is_finite (fprec (type_of_expr e)) (femax (type_of_expr e)) fv = true /\
   reval r (env_ vm) errors =
   B2R (fprec (type_of_expr e)) (femax (type_of_expr e)) fv).
Proof.
intros.
destruct s as [[t k] m].
destruct H as [errors [? [? ?]]]; exists errors; split; auto.
apply (errors_bounded_e _ t k); auto.
Qed.

Definition rndval_result  {NANS: Nans}
   (bm : boundsmap) (vm : valmap) (e : expr) r s 
  (H:  rndval_without_cond (fshift (fcval e)) = (r,s)) :=
   boundsmap_denote bm vm ->
  let '(_, m) := s in 
   exists errors: nat -> R,
     Forall (fun it => let '(i,(ty,k)) := it in 
                   Rle (Rabs (errors (pred (Pos.to_nat i)))) (error_bound ty k))
      (Maps.PTree.elements m) /\
  (let fv := fval (env_ vm) e in
   is_finite (fprec (type_of_expr e)) (femax (type_of_expr e)) fv = true /\
   reval r (env_ vm) errors =
   B2R (fprec (type_of_expr e)) (femax (type_of_expr e)) fv).

Fixpoint evenlog' (p: positive)  : Z * Z :=
 match p with 
 | xO q => match evenlog' q with (r,n) => (r, Z.succ n) end
 | _ => (Z.pos p, 0%Z)
 end.

Definition evenlog (i: Z) : Z * Z :=
 match i with
 | Z.pos p => evenlog' p
 | _ => (i,0%Z)
 end.

Lemma evenlog_e: forall i, i = (fst (evenlog i) * Z.pow 2 (snd (evenlog i)))%Z.
Proof.
intros.
unfold evenlog.
destruct i; simpl; rewrite ?Pos.mul_1_r; auto.
induction p; simpl; rewrite ?Pos.mul_1_r; auto.
destruct (evenlog' p) eqn:?H; simpl in *.
rewrite Pos2Z.inj_xO.
rewrite IHp.
rewrite Z.pow_succ_r.
lia.
clear - H.
revert z z0 H; induction p; simpl in *; intros.
inversion H; lia.
destruct (evenlog' p). inversion H; clear H; subst.
specialize (IHp _ _ (eq_refl _)).
lia.
inversion H; clear H; subst; lia.
Qed.

Lemma evenlog_nonneg: forall i, (0 <= snd (evenlog i))%Z.
Proof.
intros.
destruct i; simpl; try lia.
induction p; simpl; try lia.
destruct (evenlog' p); simpl in *.
lia.
Qed.

Definition cleanup_Fnum' f e := 
 let (f1,e1) := evenlog f in
 let e' := (e+e1)%Z
  in match e' with 
      | Zpos _ =>   IZR (f1 * Z.pow 2 e')%Z
      | Z0 => IZR f1
      | Zneg p => IZR f1 / IZR (Z.pow 2 (Zpos p))
     end.

Lemma cleanup_Fnum:
  forall f e, F2R radix2 {| Defs.Fnum := f; Defs.Fexp := e |} = cleanup_Fnum' f e.
Proof.
intros.
unfold cleanup_Fnum'.
pose proof (evenlog_e f).
pose proof (evenlog_nonneg f).
destruct (evenlog f) as [r n].
simpl in *.
subst f.
destruct (e+n)%Z eqn:?H.
- rewrite mult_IZR. 
rewrite (IZR_Zpower radix2) by auto.
rewrite Rmult_assoc.
rewrite <- bpow_plus.
rewrite Z.add_comm.
rewrite H.
apply Rmult_1_r.
-
rewrite <- H.
rewrite !mult_IZR.
rewrite Rmult_assoc.
f_equal.
rewrite  (IZR_Zpower radix2) by auto.
rewrite <- bpow_plus.
rewrite  <- (IZR_Zpower radix2) by lia.
rewrite Z.add_comm.
reflexivity.
-
rewrite !mult_IZR.
unfold Rdiv.
rewrite Rmult_assoc.
f_equal.
rewrite  !(IZR_Zpower radix2) by auto.
rewrite <- bpow_plus.
rewrite Z.add_comm.
rewrite H.
change (Z.neg p) with (Z.opp (Z.pos p)).
rewrite bpow_opp.
reflexivity.
Qed.

Definition roundoff_error_bound {NANS: Nans} (vm: valmap) (e: expr) (err: R):=
 Rle (Rabs (@FT2R (type_of_expr e) (fval (env_ vm) e) - rval (env_ vm) e)) err.

Definition prove_roundoff_bound {NANS: Nans}
    (bm: boundsmap) (vm: valmap) (e: expr) 
   (err: R): Prop := 
   boundsmap_denote bm vm ->
   roundoff_error_bound vm e err.

Ltac unfold_prove_rndval P :=
  (* Suppose you have proved a theorem P of the form, "prove_rndval bm vm e"
    where e is an expr (reified floating-point expression).
  Then in any proof goal where there is a boundsmap_denote above the line,
   use this tactic to apply-and-unfold P, for use in proving some consequence of P *)
match type of P with prove_rndval _ _ _ => idtac end;
let BMD := fresh "BMD" in 
  match goal with H: boundsmap_denote _ _ |- _ => rename H into BMD end;
let H2 := fresh "H2" in let H3 := fresh "H3" in let r := fresh "r" in let s := fresh "s" in
destruct P as [[r s] [H2 H3]];
specialize (H3 BMD);
process_boundsmap_denote;
compute in H2; inversion H2; clear H2; subst;
fold Tsingle in H3; fold Tdouble in H3;
apply rndval_with_cond_result1_e in H3;
let errors := fresh "errors" in let H0 := fresh "H0" in
destruct H3 as [errors [H0 H2]];
let e := fresh "e" in 
 match type of H2 with context [fval ?env ?ee] => 
   set (e := fval env ee) in H2;
  let e1 := eval hnf in ee in change ee with e1 in e;
  cbv beta iota zeta delta [
      fval
      fop_of_binop fop_of_rounded_binop cast_lub_l cast_lub_r
      fop_of_unop fop_of_rounded_unop fop_of_exact_unop
      option_pair_of_options] in e;
   change (type_of_expr _) with Tsingle in e;
   change (type_of_expr _) with Tdouble in e;
   try change (type_lub _ _) with Tsingle in e;
   try change (type_lub _ _) with Tdouble in e;
   repeat change (type_lub ?x ?y) with x in e;
   repeat change (type_lub ?x ?y) with y in e;
   repeat change (cast  _ _ ?x) with x in e;
   repeat 
    match goal with
    | e := context [env_ ?a ?b ?c] |- _ =>
       let u := constr:(env_ a b c) in let v := eval hnf in u in change u with v in *
   end
end;
 destruct H2 as [_ H2];
 unfold e in H2;
cbv beta iota zeta delta [
         reval Prog.binary Prog.unary Prog.real_operations
         Tree.binary_real Tree.unary_real] 
   in H2;
   repeat 
    match type of H2 with context [env_ ?a ?b ?c] =>
       let u := constr:(env_ a b c) in let v := eval hnf in u in change u with v in H2
   end;
change (Build_radix _ _) with radix2 in H2;
 (* Don't do this stuff, any rewrites in H2 make Qed blow up
repeat 
match type of H2 with
 context [ F2R radix2  {| Defs.Fnum := ?f; Defs.Fexp := ?e |} ] =>
   let H := fresh in assert (H := cleanup_Fnum f e);
      simpl Z.add in H; simpl fst in H; 
      change (powerRZ _ 0) with 1%R in H;
      rewrite H in H2; clear H
end;
rewrite ?Rmult_1_l in H2;
*)
change (type_of_expr _) with Tsingle in *;
change (type_of_expr _) with Tdouble in *;
fold (@FT2R Tsingle) in *;
fold (@FT2R Tdouble) in *;
repeat (let E := fresh "E" in 
            assert (E := Forall_inv H0); simpl in E;
          match type of E with
           |  Rle (Rabs ?a) (error_bound _ Normal') => 
                let d := fresh "d" in set (d := a) in *; clearbody d
           |  Rle (Rabs ?a) (error_bound _ Denormal') => 
                let d := fresh "e" in set (d := a) in *; clearbody d
           |  Rle (Rabs ?a) (error_bound _ Denormal2') => 
                   let d := fresh "e" in set (d := a) in *; clearbody d
           end;
           unfold error_bound in E;
           simpl bpow in E;
           rewrite Zpower_pos_powerRZ in E; 
           rewrite mul_hlf_powerRZ in E;
           simpl Z.sub in E;
           apply Forall_inv_tail in H0);
match type of H0 with Forall _ nil => clear H0 end;
clear errors;
fold e in H2;
revert H2; intro.

Ltac prove_IZR_neq :=
 change R0 with 0%R; 
 let H := fresh in intro H; apply eq_IZR in H; discriminate H.

Lemma powerRZ_compute:
 forall b i, powerRZ (IZR (Zpos b)) (Zpos i)  = IZR (Z.pos (Pos.pow b i)).
Proof.
intros.
unfold powerRZ.
rewrite pow_IZR.
f_equal.
rewrite Pos2Z.inj_pow.
f_equal.
apply positive_nat_Z.
Qed.

Ltac compute_powerRZ := 
change (powerRZ ?b (Z.neg ?x)) with (powerRZ b (Z.opp (Z.pos x))) in *;
rewrite <- power_RZ_inv in *
  by (let H := fresh  in intro H; apply eq_IZR in H; discriminate H);
rewrite powerRZ_compute in *;
repeat match goal with
 | |- context [Pos.pow ?a ?b] =>
  let x := constr:(Pos.pow a b) in let y := eval compute in x in
  change x with y in *
 | H: context [Pos.pow ?a ?b] |- _ =>
  let x := constr:(Pos.pow a b) in let y := eval compute in x in
  change x with y in *
end.

Ltac prove_roundoff_bound2 :=
 match goal with P: prove_rndval _ _ _ |- prove_roundoff_bound _ _ _ _ =>
   intro; unfold_prove_rndval P
 end;
 (* Unfold roundoff_error_bound *)
 red;
 (* The fval below the line should match the e above the line *)
 match goal with e := _ : ftype _ |- _ =>
     change (fval _ _) with e; clearbody e
 end;
 (* unfold rval *)
 match goal with |- context [rval ?env ?x] =>
   let a := constr:(rval env x) in let b := eval hnf in a in change a with b
 end;
 cbv beta iota delta [rval Rop_of_binop Rop_of_unop
            Rop_of_rounded_binop Rop_of_exact_unop Rop_of_rounded_unop];
 change (type_of_expr _) with Tsingle; 
 change (type_of_expr _) with Tdouble;
 fold (@FT2R Tsingle) in *; fold (@FT2R Tdouble);

 (* incorporate the equation above the line *)
match goal with H: _ = @FT2R _ _ |- _ => rewrite <- H; clear H end;
 (* Perform all env lookups *)
 repeat 
    match goal with
    | |- context [env_ ?a ?b ?c] =>
       let u := constr:(env_ a b c) in let v := eval hnf in u in change u with v
   end;
 (* Clean up all FT2R constants *)
 repeat match goal with
 | |- context [@FT2R ?t (b32_B754_finite ?s ?m ?e ?H)] =>
 let j := fresh "j" in 
  set (j :=  @FT2R t (b32_B754_finite s m e H));
  simpl in j; subst j
 | |- context [@FT2R ?t (b64_B754_finite ?s ?m ?e ?H)] =>
 let j := fresh "j" in 
  set (j :=  @FT2R t (b64_B754_finite s m e H));
  simpl in j; subst j
 end;
 rewrite <- ?(F2R_eq radix2);
 (* clean up all   F2R radix2 {| Defs.Fnum := _; Defs.Fexp := _ |}   *)
 rewrite ?cleanup_Fnum;
 repeat match goal with |- context [cleanup_Fnum' ?f ?e] =>
  let x := constr:(cleanup_Fnum' f e) in
  let y := eval cbv - [Rdiv IZR] in x in
  change x with y
 end;
 (* Abstract all FT2R variables *)
 repeat 
  match goal with |- context [@FT2R ?t ?e] =>
     is_var e;
     let e' := fresh e in
     set (e' := @FT2R Tsingle e) in *; clearbody e'; clear e; rename e' into e
  end;
 (* clean up all powerRZ expressions *)
 compute_powerRZ.
 (* Don't do field simplify , it can blow things up, and the interval tactic
   doesn't actually need it.
 match goal with |- context [Rabs ?a <= _] => field_simplify a end.
*)

Ltac prove_roundoff_bound :=
 match goal with |- prove_roundoff_bound ?bm ?vm ?e _ =>
  assert (P: prove_rndval bm vm e)
 end.

Lemma roundoff_bound_hack:
  forall i j k, 
    (0 < i)%Z -> (0 < j)%Z -> (0 < k)%Z ->
    forall u,
    (Z.div j i = u)%Z ->
    (u >= k)%Z ->
    (IZR i / IZR j <= / (IZR k))%R.
Proof.
intros.
subst u. rename H3 into H2.
pose proof (IZR_lt _ _ H).
pose proof (IZR_lt _ _ H0).
pose proof (IZR_lt _ _ H1).
rewrite <- Rinv_Rdiv by lra.
apply Rinv_le. lra.
apply Rcomplements.Rle_div_r.
lra.
rewrite <- mult_IZR.
apply IZR_le.
pose proof (Zmod_eq j i ltac:(lia)).
assert (j/i * i = j - j mod i)%Z by lia.
apply Zmult_ge_compat_r with (p:=i) in H2; [ | lia].
rewrite H7 in H2.
pose proof (Z.mod_bound_pos j i ltac:(lia) ltac:(lia)).
lia.
Qed.

Definition bound_contains (i1 i2: ident * varinfo) :=
        (fst i1 = fst i2 /\ fst i1 = var_name (snd i1) /\ fst i2 = var_name (snd i2))
  /\ var_type (snd i1) = var_type (snd i2)
  /\   Rle (var_lobound (snd i1)) (var_lobound (snd i2))
  /\  Rge (var_hibound (snd i1)) (var_hibound (snd i2)).

Lemma Forall2_e1:
  forall {A B: Type} (f: A -> B -> Prop) al bl,
  Forall2 f al bl -> 
  (forall x, In x al -> exists y, In y bl /\ f x y).
Proof.
induction 1; intros.
inversion H.
inversion H1; clear H1; subst.
exists y; split; auto. left; auto.
destruct (IHForall2 _ H2) as [y1 [? ?]].
exists y1; split; auto.
right; auto.
Qed.

Lemma Forall2_e2:
  forall {A B: Type} (f: A -> B -> Prop) al bl,
  Forall2 f al bl -> 
  (forall y, In y bl -> exists x, In x al /\ f x y).
Proof.
induction 1; intros.
inversion H.
inversion H1; clear H1; subst.
exists x; split; auto. left; auto.
destruct (IHForall2 _ H2) as [x1 [? ?]].
exists x1; split; auto.
right; auto.
Qed.

Definition boundsmap_contains bm1 bm2 :=
  Forall2 bound_contains (Maps.PTree.elements bm1)
      (Maps.PTree.elements bm2).

Lemma boundsmap_denote_relax {NANS: Nans}:
 forall (bm1 bm2 : Maps.PTree.t varinfo)
          (vm : valmap),
  boundsmap_contains bm1 bm2 ->
      boundsmap_denote bm2 vm ->
     boundsmap_denote bm1 vm.
Proof.
intros.
intro i; specialize (H0 i).
destruct (Maps.PTree.get i bm1)  as [[t1 n1 lo1 hi1]|] eqn:?H.
-
destruct (Forall2_e1 _ _ _ H _ (Maps.PTree.elements_correct _ _ H1))
 as [[i' [t2 n2 lo2 hi2]] [? [[? [? ?]] [? [? ?]]]]]; simpl in *; subst.
apply Maps.PTree.elements_complete in H2.
rewrite H2 in H0.
destruct (Maps.PTree.get n2 vm); try contradiction; auto.
destruct H0 as [? [? [? ?]]]; subst.
split; [ | split; [ | split]]; auto.
lra.
-
destruct (Maps.PTree.get i bm2) eqn:?H; auto.
destruct (Forall2_e2 _ _ _ H _ (Maps.PTree.elements_correct _ _ H2)) 
 as [[i' ?] [? [[? _] _]]].
simpl in H4; subst.
apply Maps.PTree.elements_complete in H3.
congruence.
Qed.

Lemma prove_roundoff_bound_relax {NANS: Nans}:
  forall bm1 bm2 vm e R,
    boundsmap_contains bm1 bm2 ->
 prove_roundoff_bound bm1 vm e R ->
 prove_roundoff_bound bm2 vm e R.
Proof.
intros.
intro; apply H0.
revert H1.
apply boundsmap_denote_relax; auto.
Qed.


Definition val_bound {NANS: Nans} (vm: valmap) (e: expr) (b: R):=
 Rle (Rabs (@FT2R (type_of_expr e) (fval (env_ vm) e))) b.

Definition prove_val_bound {NANS: Nans}
    (bm: boundsmap) (vm: valmap) (e: expr) 
   (b: R): Prop := 
   boundsmap_denote bm vm ->
   val_bound vm e b.

Ltac prove_val_bound :=
 match goal with |- prove_val_bound ?bm ?vm ?e _ =>
  assert (P: prove_rndval bm vm e)
 end.

Ltac prove_val_bound2 :=
 match goal with P: prove_rndval _ _ _ |- prove_val_bound _ _ _ _ =>
   intro; unfold_prove_rndval P
 end;
 (* Unfold val_bound *)
 red;
 (* The fval below the line should match the e above the line *)
 match goal with e := _ : ftype _ |- _ =>
     change (fval _ _) with e; clearbody e
 end;
 (* cleanups *)
 change (type_of_expr _) with Tsingle; 
 change (type_of_expr _) with Tdouble;
 fold (@FT2R Tsingle) in *; fold (@FT2R Tdouble);
 (* incorporate the equation above the line *)
match goal with H: _ = @FT2R _ _ |- _ => rewrite <- H; clear H end;
 (* Perform all env lookups *)
 repeat 
    match goal with
    | |- context [env_ ?a ?b ?c] =>
       let u := constr:(env_ a b c) in let v := eval hnf in u in change u with v
   end;
 (* Clean up all FT2R constants *)
 repeat match goal with
 | |- context [@FT2R ?t (b32_B754_finite ?s ?m ?e ?H)] =>
 let j := fresh "j" in 
  set (j :=  @FT2R t (b32_B754_finite s m e H));
  simpl in j; subst j
 | |- context [@FT2R ?t (b64_B754_finite ?s ?m ?e ?H)] =>
 let j := fresh "j" in 
  set (j :=  @FT2R t (b64_B754_finite s m e H));
  simpl in j; subst j
 end;
 rewrite <- ?(F2R_eq radix2);
 (* clean up all   F2R radix2 {| Defs.Fnum := _; Defs.Fexp := _ |}   *)
 rewrite ?cleanup_Fnum;
 repeat match goal with |- context [cleanup_Fnum' ?f ?e] =>
  let x := constr:(cleanup_Fnum' f e) in
  let y := eval cbv - [Rdiv IZR] in x in
  change x with y
 end;
 (* Abstract all FT2R variables *)
 repeat 
  match goal with |- context [@FT2R ?t ?e] =>
     is_var e;
     let e' := fresh e in
     set (e' := @FT2R Tsingle e) in *; clearbody e'; clear e; rename e' into e
  end;
 (* clean up all powerRZ expressions *)
 compute_powerRZ.
 (* Don't do field simplify , it can blow things up, and the interval tactic
   doesn't actually need it.
 match goal with |- context [Rabs ?a <= _] => field_simplify a end.
*)



