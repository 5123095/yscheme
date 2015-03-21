;;;Shiv Indap
;;;sindap
;;;Assignment 8
;;;P523
;;; Andy Keep, Kent Dybvig
;;; P423/P523
;;; Spring 2009

;;; verify-scheme accept a single value and verifies that the value
;;; is a valid program in the grammar of the fourth assignment
;;;
;;; Grammar for verify-scheme (assignment 7):
;;;
;;;Program	--------->	(letrec ([label (lambda (uvar*) Body)]*) Body)
;;;Body	--------->	(locals (uvar*) Tail)
;;;Tail	--------->	Triv
;;;	|	(alloc Value)
;;;	|	(mref Value Value)
;;;	|	(binop Value Value)
;;;	|	(Value Value*)
;;;	|	(if Pred Tail Tail)
;;;	|	(begin Effect* Tail)
;;;Pred	--------->	(true)
;;;	|	(false)
;;;	|	(relop Value Value)
;;;	|	(if Pred Pred Pred)
;;;	|	(begin Effect* Pred)
;;;Effect	--------->	(nop)
;;;	|	(set! uvar Value)
;;;	|	(mset! Value Value Value)
;;;	|	(Value Value*)
;;;	|	(if Pred Effect Effect)
;;;	|	(begin Effect* Effect)
;;;Value	--------->	Triv
;;;	|	(alloc Value)
;;;	|	(mref Value Value)
;;;	|	(binop Value Value)
;;;	|	(Value Value*)
;;;	|	(if Pred Value Value)
;;;	|	(begin Effect* Value)
;;;Triv	--------->	uvar | int | label
;;;
;;; Where uvar is symbol.n where (n >= 0)
;;;       binop is +, -, *, logand, logor, or sra
;;;       predop is <, <=, or =
;;;       label is symbol$n where (n >= 0)
;;;
;;; If the value is a valid program, verify uil returns the value
;;; unchanged; otherwise it signals an error.
;;;
;;; At this level in the compiler verify-scheme no longer checks machine
;;; constraints, as select-instructions should now perform instruction
;;; selection and correctly select which instruction to use based on the
;;; machine constraints.


;;;verify-uil is very similar to the verify-scheme of the previous assignments all it does is simply add checks for mref and alloc in Tail and Value helpers
;;;and mset! in Effect helper
(define-who verify-uil
  (define verify-x-list
    (lambda (x* x? what)
      (let loop ([x* x*] [idx* '()])
        (unless (null? x*)
		(let ([x (car x*)] [x* (cdr x*)])
		  (unless (x? x)
			  (error who "invalid ~s ~s found" what x))
		  (let ([idx (extract-suffix x)])
		    (when (member idx idx*)
			  (error who "non-unique ~s suffix ~s found" what idx))
		    (loop x* (cons idx idx*))))))))
  (define Triv
    (lambda (label* uvar*)
      (lambda (t)
        (unless (or (label? t) (uvar? t) (and (integer? t) (exact? t)))
		(error who "invalid Triv ~s" t))
        (when (and (integer? t) (exact? t))
	      (unless (int64? t)
		      (error who "integer out of 64-bit range ~s" t)))
        (when (uvar? t)
	      (unless (memq t uvar*)
		      (error who "reference to unbound uvar ~s" t)))
        (when (label? t)
	      (unless (memq t label*)
		      (error who "unbound label ~s" t)))
        t)))
  (define Value
    (lambda (label* uvar*)
      (lambda (val)
        (match val
	       [(if ,[(Pred label* uvar*) -> test] ,[conseq] ,[altern]) (void)]
	       [(begin ,[(Effect label* uvar*) -> ef*] ... ,[val]) (void)]
	       [(alloc ,[(Value label* uvar*) -> mem-size]) (void)]	;;clause for alloc
	       [(mref ,[(Value label* uvar*) -> base] ,[(Value label* uvar*) -> offset]) (void)] ;;clause for mref
	       [(sra ,[x] ,y)
		(unless (uint6? y)
			(error who "invalid sra operand ~s" y))]
	       [(,binop ,[x] ,[y])
		(guard (memq binop '(+ - * logand logor sra)))
		(void)]
	       [(,[rator] ,[rand*] ...) (void)]
	       [,[(Triv label* uvar*) -> tr] (void)]))))
  (define Effect
    (lambda (label* uvar*)
      (lambda (ef)
        (match ef
	       [(nop) (void)]
	       [(if ,[(Pred label* uvar*) -> test] ,[conseq] ,[altern]) (void)]
	       [(begin ,[ef*] ... ,[ef]) (void)]
	       [(set! ,var ,[(Value label* uvar*) -> val])
		(unless (memq var uvar*)
			(error who "assignment to unbound var ~s" var))]
	       [(mset! ,[(Value label* uvar*) -> base] ,[(Value label* uvar*) -> offset] ,[(Value label* uvar*) -> val]) (void)] ;;clause for mset!
	       [(,[(Value label* uvar*) -> rator] 
		 ,[(Value label* uvar*) -> rand*] ...)
		(void)]
	       [,ef (error who "invalid Effect ~s" ef)]))))
  (define Pred
    (lambda (label* uvar*)
      (lambda (pr)
        (match pr
	       [(true) (void)]
	       [(false) (void)]
	       [(if ,[test] ,[conseq] ,[altern]) (void)]
	       [(begin ,[(Effect label* uvar*) -> ef*] ... ,[pr]) (void)]
	       [(,predop ,[(Value label* uvar*) -> x] ,[(Value label* uvar*) -> y])
		(unless (memq predop '(< > <= >= =))
			(error who "invalid predicate operator ~s" predop))]
	       [,pr (error who "invalid Pred ~s" pr)]))))
  (define Tail
    (lambda (tail label* uvar*)
      (match tail
	     [(if ,[(Pred label* uvar*) -> test] ,[conseq] ,[altern]) (void)]
	     [(begin ,[(Effect label* uvar*) -> ef*] ... ,[tail]) (void)]
	     [(alloc ,[(Value label* uvar*) -> mem-size]) (void)]			;;clause for alloc
	     [(mref ,[(Value label* uvar*) -> base] ,[(Value label* uvar*) -> offset]) (void)] ;;clause for mref
	     [(sra ,[(Value label* uvar*) -> x] ,y)
	      (unless (uint6? y)
		      (error who "invalid sra operand ~s" y))]
	     [(,binop ,[(Value label* uvar*) -> x] ,[(Value label* uvar*) -> y])
	      (guard (memq binop '(+ - * logand logor sra)))
	      (void)]
	     [(,[(Value label* uvar*) -> rator] 
	       ,[(Value label* uvar*) -> rand*] ...)
	      (void)]
	     [,[(Triv label* uvar*) -> triv] (void)])))
  (define Body
    (lambda (label*)
      (lambda (bd fml*)
        (match bd
	       [(locals (,local* ...) ,tail)
		(let ([uvar* `(,fml* ... ,local* ...)])
		  (verify-x-list uvar* uvar? 'uvar)
		  (Tail tail label* uvar*))]
	       [,bd (error who "invalid Body ~s" bd)]))))
  (lambda (x)
    (match x
	   [(letrec ([,label* (lambda (,fml** ...) ,bd*)] ...) ,bd)
	    (verify-x-list label* label? 'label)
	    (map (lambda (fml*) (verify-x-list fml* uvar? 'formal)) fml**)
	    (for-each (Body label*) bd* fml**)
	    ((Body label*) bd '())]
	   [,x (error who "invalid Program ~s" x)])
    x))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

;;;When I encounter any function calls in Value and effect contexts it simply calls trivialize calls, thats the only change from last weeks assignment
;;;To deal with new forms introduced by this weeks grammar I am trivializing the arguments to all the mref mset! and alloc 
;;; eg (set! x.1 (alloc (begin (set! y.2 16) (set! z.3 32) (+ y.2 z.3)))) wiil get translated to
;;;(begin
;;;(set! y.2 16)
;;;(set! z.3 32)
;;;(set! t.4 (+ y.2 z.3))
;;;(set! x.1 (alloc t.4)))
;;;It will be similar if we encounter mrefs and mset! with complex arguments
;;;I am treating an mref as an ordinary binop for this pass as it produces the exactly same output as any other binop
;;;clauses are added for mset! in Effect and alloc in tail and value contexts

(define-who remove-complex-opera*
  (define (Body bd)
    (define new-local* '())
    (define (new-t)
      (let ([t (unique-name 't)])
        (set! new-local* (cons t new-local*))
        t))
    (define (trivialize-call expr*)
      (let-values ([(call set*) (break-down-expr* expr*)])
        (make-begin `(,@set* ,call))))
    (define break-down-expr*
      (lambda (expr*)
	(match expr*
	       [() (values '() '())]
	       [(alloc . ,[break-down-expr* -> rest* set*])
		(values `(alloc ,rest* ...) set*)]
	       [(mset! . ,[break-down-expr* -> rest* set*])
		(values `(mset! ,rest* ...) set*)]
	       [(,s . ,[break-down-expr* -> rest* set*]) 
		(guard (simple? s)) 
		(values `(,s ,rest* ...) set*)]
	       [(,[Value -> expr] . , [break-down-expr* -> rest* set*])
		(let ([t (new-t)]) 
		  (values `(,t ,rest* ...) `((set! ,t ,expr) ,set* ...)))]
	       [,expr* (error who "invalid Expr ~s" expr*)])))
    (define (simple? x)
      (or (uvar? x) (label? x) (and (integer? x) (exact? x))
          (memq x '(+ - * logand logor sra mref)) (memq x '(= < <= > >=))))
    (define Value
      (lambda (val)
	(match val
	       [(if ,[Pred -> test] ,[conseq] ,[altern]) `(if ,test ,conseq ,altern)]
	       [(begin ,[Effect -> ef*] ... ,[val]) (make-begin `(,ef* ... ,val))]
	       [(alloc ,[Value -> val]) (trivialize-call `(alloc ,val))]
	       [(,binop ,[Value -> x] ,[ Value -> y])
		(guard (memq binop '(+ - * logand logor sra mref)))
		(trivialize-call `(,binop ,x ,y))]
	       [(,rator ,rand* ...) (trivialize-call `(,rator ,rand* ...))]
	       [,tr tr])))
    (define (Effect ef)
      (match ef
	     [(nop) '(nop)]
	     [(mset! ,[Value -> val1] ,[Value -> val2] ,[Value -> val3]) (trivialize-call `(mset! ,val1 ,val2 ,val3))]
	     [(if ,[Pred -> test] ,[conseq] ,[altern]) `(if ,test ,conseq ,altern)]
	     [(begin ,[ef*] ... ,[ef]) (make-begin `(,ef* ... ,ef))]
	     [(set! ,var ,[Value -> val]) `(set! ,var ,val)]
	     [(,rator ,rand* ...) (trivialize-call `(,rator ,rand* ...))]
	     [,ef (error who "invalid Effect ~s" ef)]))
    (define (Pred pr)
      (match pr
	     [(true) '(true)]
	     [(false) '(false)]
	     [(if ,[test] ,[conseq] ,[altern]) `(if ,test ,conseq ,altern)]
	     [(begin ,[Effect -> ef*] ... ,[pr]) (make-begin `(,ef* ... ,pr))]
	     [(,predop ,x ,y)
	      (guard (memq predop '(< <= = >= >)))
	      (trivialize-call `(,predop ,x ,y))]
	     [,pr (error who "invalid Pred ~s" pr)]))
    (define (Tail tail)
      (match tail
	     [(if ,[Pred -> test] ,[conseq] ,[altern]) `(if ,test ,conseq ,altern)]
	     [(begin ,[Effect -> ef*] ... ,[tail]) (make-begin `(,ef* ... ,tail))]
	     [(alloc ,[Value -> val]) (trivialize-call `(alloc ,val))]
	     [(,binop ,[Value -> x] ,[Value -> y])
	      (guard (memq binop '(+ - * logand logor sra mref)))
	      (trivialize-call `(,binop ,x ,y))]
	     [(,rator ,rand* ...) (trivialize-call `(,rator ,rand* ...))]
	     [,tr tr]))
    (match bd
	   [(locals (,local* ...) ,[Tail -> tail])
	    `(locals (,local* ... ,new-local* ...) ,tail)]
	   [,bd (error who "invalid Body ~s" bd)]))
  (lambda (x)
    (match x
	   [(letrec ([,label* (lambda (,fml** ...) ,[Body -> bd*])] ...) 
	      ,[Body -> bd])
	    `(letrec ([,label* (lambda (,fml** ...) ,bd*)] ...) ,bd)]
	   [,x (error who "invalid Program ~s" x)])))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;; I decided to get rid of the alloc forms in this pass by introducing the allocaton pointer register;
;;; There are 2 essential places where the alloc form will be encountered
;;; a) tail context and b) Value context
;;; if i encounter alloc in tail context e.g (alloc 48)
;;; all I do is convert it into 3 statements (alloc 48) => (begin (set! temp.1 ap) (set! ap (+ ap 48)) temp.1)
;;; if i encounter alloc in value context e.g (set! x.2 (alloc 48))
;;; all I do is convert it into 2 statements (set! x.2 (alloc 48)) => (begin (set! x.2 ap) (set! ap (+ ap 48)))
;;; mrefs continue to be treated as binops
;;; msets are allowed to pass on as it is

(define-who flatten-set!
  (define (Body bd)
    (define trivialize-set!
      (lambda (lhs rhs)
	(match rhs
	       [(if ,[Pred -> test] ,[conseq] ,[altern]) `(if ,test ,conseq ,altern)]
	       [(begin ,[Effect -> ef*] ... ,[tail]) (make-begin `(,ef* ... ,tail))]
	       [(alloc ,val1) (make-begin 
			       `((set! ,lhs ,allocation-pointer-register) 
				 (set! ,allocation-pointer-register (+ ,allocation-pointer-register ,val1))))]
	       [(,binop ,x ,y) 
		(guard (memq binop '(+ - * logand logor sra mref)))
		`(set! ,lhs (,binop ,x ,y))]
	       [(,rator ,rand* ...) `(set! ,lhs (,rator ,rand* ...))] ;This will make it (set! t.1 (ack$0 2 3)) and push the expression to the end
	       [,tr `(set! ,lhs ,tr)]))) ;;treating mref's as binop
    (define Effect
      (lambda (ef)
	(match ef
	       [(nop) '(nop)]
	       [(if ,[Pred -> test] ,[conseq] ,[altern]) `(if ,test ,conseq ,altern)]
	       [(begin ,[Effect -> ef*] ... ,[ef]) (make-begin `(,ef* ... ,ef))]
	       [(mset! ,base ,offset ,value) `(mset! ,base ,offset ,value)]
	       [(set! ,var ,val) (trivialize-set! var val)]
	       [(,rator ,rand* ...) `(,rator ,rand* ...)]
	       [,ef (error who "invalid Effect ~s" ef)])))
    (define (Pred pr)
      (match pr
	     [(true) '(true)]
	     [(false) '(false)]
	     [(if ,[test] ,[conseq] ,[altern]) `(if ,test ,conseq ,altern)]
	     [(begin ,[Effect -> ef*] ... ,[pr]) (make-begin `(,ef* ... ,pr))]
	     [(,predop ,x ,y)
	      (guard (memq predop '(< <= = >= >)))
	      `(,predop ,x ,y)]
	     [,pr (error who "invalid Pred ~s" pr)]))
    (define (Tail tail) 
      (match tail
	     [(if ,[Pred -> test] ,[conseq] ,[altern]) `(if ,test ,conseq ,altern)]
	     [(begin ,[Effect -> ef*] ... ,[tail]) (make-begin `(,ef* ... ,tail))]
	     [(alloc ,val)
	      (let ((new-temp (new-t)))
		(make-begin `((set! ,new-temp ,allocation-pointer-register) 
			      (set! ,allocation-pointer-register (+ ,allocation-pointer-register ,val))
			      ,new-temp)))]
	     [(,binop ,x ,y)
	      (guard (memq binop '(+ - * logand logor sra mref)))
	      `(,binop ,x ,y)]
	     [(,rator ,rand* ...) `(,rator ,rand* ...)]
	     [,tr tr]))
    (define new-local* '())
    (define (new-t)
      (let ([t (unique-name 't)])
	(set! new-local* (cons t new-local*))
	t))
    (match bd
	   [(locals (,uvar* ...) ,[Tail -> tail]) `(locals (,uvar* ...,new-local* ...) ,tail)]
	   [,bd (error who "invalid Body ~s" bd)]))
  (lambda (x)
    (match x
	   [(letrec ([,label* (lambda (,fml** ...) ,[Body -> bd*])] ...)
	      ,[Body -> bd])
	    `(letrec ([,label* (lambda (,fml** ...) ,bd*)] ...) ,bd)]
	   [,x (error who "invalid Program ~s" x)])))

;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

;;;Program	----->	(letrec ([label (lambda (uvar*) Body)]*) Body)
;;;Body	----->	(locals (uvar*) Tail)
;;;Tail	----->	Triv
;;;	|	(binop Triv Triv)
;;;	|	(Triv Triv*)
;;;     |       (mref Triv Triv)
;;;	|	(if Pred Tail Tail)
;;;	|	(begin Effect* Tail)
;;;Pred	----->	(true)
;;;	|	(false)
;;;	|	(relop Triv Triv)
;;;	|	(if Pred Pred Pred)
;;;	|	(begin Effect* Pred)
;;;Effect	----->	(nop)
;;;	|	(set! uvar Triv)
;;;	|	(set! uvar (binop Triv Triv))
;;;	|	(set! uvar (Triv Triv*))
;;;     |       (mset! Triv Triv Triv)
;;;	|	(Triv Triv*)
;;;	|	(if Pred Effect Effect)
;;;	|	(begin Effect* Effect)
;;;Triv	----->	uvar | int | label

;;;Now That I have got rid of the alloc forms impose calling conventions is trivial....
;;;mref continues to be treated as binop and mset! expressions are passed on as they are
;;; Though only addition is that the allocation pointer register is added here to the list of registers 
;;; that are live on entry...This helps in allocating registers properly to conflicting variables, otherwise me may
;;;happen to override the alocation pointer regster and access wrong regions in the memory

(define-who impose-calling-conventions
  (define (argument-locations fmls idx->fv)
    (let f ([fmls fmls] [regs parameter-registers] [fv-idx 0])
      (cond
       [(null? fmls) '()]
       [(null? regs) (cons (idx->fv fv-idx) (f (cdr fmls) regs (+ fv-idx 1)))]
       [else (cons (car regs) (f (cdr fmls) (cdr regs) fv-idx))])))
  (define (index->new-frame-var idx) (unique-name 'nfv))
  ;;Filters  list for values based on the predicate passed by fn
  (define filter 			
    (lambda (fn ls)	
      (cond
       [(null? ls) '()]
       [(fn (car ls)) (cons (car ls) (filter fn (cdr ls)))]
       [else (filter fn (cdr ls))])))
  (define trivial?
    (lambda (x)
      (or (uvar? x) (integer? x) (label? x) (register? x))))
  (define (Body bd fml*)
    (define new-frame-var** '())  ;;Stores all the nfv assignments
    (define Effect
      (lambda (effect)
	(match effect
	       [(nop) '(nop)]
	       [(if ,[Pred -> pred] ,[Effect -> conseq] ,[Effect -> alt]) `(if ,pred ,conseq ,alt)]
	       [(begin ,[Effect -> ef*] ... ,[Effect -> ef]) (make-begin `(,ef* ... ,ef))]
	       [(mset! ,base ,offset ,val) effect]
	       [(set! ,uvar ,triv) (guard (trivial? triv)) effect]					
	       [(set! ,uvar (,binop ,x ,y)) (guard (memq binop '(+ - * logand logor sra mref))) effect]
	       [(set! ,uvar (,triv ,triv* ...)) 
		(guard (trivial? triv))
		(make-begin `(,(Effect `(,triv ,triv* ...)) (set! ,uvar ,return-value-register)))]												
	       [(,triv ,triv* ...)	
					;This handles non tail call in Effect Context
		(let* ((return-point-var (unique-label 'rp))
		       (fml-loc* (argument-locations triv* index->new-frame-var)) ;Assign a register or variable to each formal parameter
		       (expr (make-begin 
			      `((set! ,fml-loc* ,triv*) ... (set! ,return-address-register ,return-point-var) (,triv ,return-address-register ,frame-pointer-register ,allocation-pointer-register ,@fml-loc*))))
		       (return-point-expr `(return-point ,return-point-var ,expr))) ;Create a return-point-expr
		  (set! new-frame-var** (cons (filter uvar? fml-loc*) new-frame-var**))
		  (make-begin `(,return-point-expr)))])))
    (define (Pred pred) 
      (match pred
	     [(true) '(true)]
	     [(false) '(false)]
	     [(if ,[test] ,[conseq] ,[altern]) `(if ,test ,conseq ,altern)]
	     [(begin ,[Effect -> ef*] ... ,[pr]) (make-begin `(,ef* ... ,pr))]
	     [(,predop ,x ,y)
	      (guard (memq predop '(< <= = >= >)))
	      `(,predop ,x ,y)]))
    (define Tail
      (lambda (tail rp)
	(match tail
	       [(begin ,[Effect -> ef*] ... ,tail) 
		(let ((tail-expr (Tail tail rp)))
		  (make-begin `(,ef* ... ,tail-expr)))]
	       [(if ,[Pred -> pred] ,conseq ,alt)
		(let ((conseq-expr (Tail conseq rp))
		      (alt-expr (Tail alt rp)))
		  `(if ,pred ,conseq-expr ,alt-expr))]
	       [(,binop ,x ,y) (guard (memq binop '(+ - * logand logor sra mref)))
		(let ((expr `((set! ,return-value-register ,tail) (,rp ,frame-pointer-register ,allocation-pointer-register ,return-value-register))))
		  (make-begin expr))]
	       [(,triv ,triv* ...) 
		(let ((fml-loc* (reverse (argument-locations triv* index->frame-var))) (triv* (reverse triv*)))
		  (make-begin 
		   `((set! ,fml-loc* ,triv*) ... (set! ,return-address-register ,rp) (,triv ,return-address-register ,frame-pointer-register ,allocation-pointer-register ,@fml-loc*))))]
	       [,triv 	(let ((return-value-expr `(set! ,return-value-register ,triv))
			      (return-calling-expr `(,rp ,frame-pointer-register ,allocation-pointer-register ,return-value-register)))
			  (make-begin `(,return-value-expr ,return-calling-expr)))])))
    (match bd
	   [(locals (,local* ...) ,tail)
	    (let ([rp (unique-name 'rp)]
		  [fml-loc* (argument-locations fml* index->frame-var)])
	      (let ([tail (Tail tail rp)])
		`(locals (,rp ,fml* ... ,local* ... ,new-frame-var** ... ...)
			 (new-frames (,new-frame-var** ...)
				     ,(make-begin 
				       `((set! ,rp ,return-address-register)
					 (set! ,fml* ,fml-loc*) ...
					 ,tail))))))]
	   [,bd (error who "invalid Body ~s" bd)]))
  (lambda (x)
    (match x
	   [(letrec ([,label* (lambda (,fml** ...) ,bd*)] ...) ,bd)
	    (let ([bd* (map Body bd* fml**)] [bd (Body bd '())])
	      `(letrec ([,label* (lambda () ,bd*)] ...) ,bd))]
	   [,x (error who "invalid Program ~s" x)])))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

;;;Program	----->	(letrec ([label (lambda () Body)]*) Body)
;;;Body	----->	(locals (uvar*)
;;;		  (new-frames (Frame*) Tail))
;;;Frame	----->	(uvar*)
;;;Tail	----->	(Triv Loc*)
;;;	|	(if Pred Tail Tail)
;;;	|	(begin Effect* Tail)
;;;Pred	----->	(true)
;;;	|	(false)
;;;	|	(relop Triv Triv)
;;;	|	(if Pred Pred Pred)
;;;	|	(begin Effect* Pred)
;;;Effect	----->	(nop)
;;;	|	(set! Var Triv)
;;;	|	(set! Var (binop Triv Triv))
;;;	|	(return-point label (Triv Loc*))
;;;	|	(if Pred Effect Effect)
;;;	|	(begin Effect* Effect)
;;;Loc	----->	reg | fvar
;;;Var	----->	uvar | Loc
;;;Triv	----->	Var | int | label

;;;uncover frame conflicts needs to handle mrefs and mset's in different way while updating the conflict table
;;;(set! x (mref base offset)) => will mean that x conflicts with both base and offset and hence we must record these conflicts
;;;(mset! base offset value) => in this we have to record the conflicts of each parameters with the other

(define-who uncover-frame-conflict
  (define add-conflicts!
    (lambda (ct lhs live*)
      (define add-conflict!
	(lambda (var1 var2)
	  (let ([a (assq var1 ct)])
	    (set-cdr! a (if (eq? var1 var2) (cdr a)  (set-cons var2 (cdr a)))))))
      (when (uvar? lhs)
	    (for-each
	     (lambda (live) (add-conflict! lhs live))
	     live*))
      (for-each
       (lambda (live) (when (and (uvar? live) (not (register? lhs))) (add-conflict! live lhs)))
       live*)))
  (define trivial?
    (lambda (x)
      (or (uvar? x) (integer? x) (label? x))))
  (define remove-nulls
    (lambda (ls)
      (cond
       [(null? ls) '()]
       [(null? (car ls)) (remove-nulls (cdr ls))]
       [else (set-cons (car ls) (remove-nulls (cdr ls)))])))
  (define (Body x)
    (define call-live* '())
    (define Triv (lambda (x) (if (or (uvar? x) (frame-var? x)) `(,x) '())))
    (define Effect*
      (lambda (x live* ct)
        (match x
	       [() live*]
	       [(,ef* ... ,ef) (Effect* ef* (Effect ef live* ct) ct)]
	       [,x (error who "invalid Effect* list ~s" x)])))
    (define Effect
      (lambda (x live* ct)
        (match x
	       [(nop) live*]
	       [(if ,test ,[c-live*] ,[a-live*]) 
		(Pred test  c-live* a-live* ct)]
	       [(begin ,ef* ... ,[live*]) (Effect* ef* live* ct)]
	       [(mset! ,[Triv -> base] ,[Triv -> offset] ,[Triv -> value])
		(begin
		  (if (not (null? base)) (add-conflicts! ct (car base) (union offset value live*)))
		  (if (not (null? offset)) (add-conflicts! ct (car offset) (union base value live*)))
		  (if (not (null? value)) (add-conflicts! ct (car value) (union offset base live*)))
		  (union base offset value live*))]
	       [(set! ,lhs (mref ,[Triv -> x-live*] ,[Triv -> y-live*]))
		(begin
		  (add-conflicts! ct lhs (union x-live* y-live* live*))
		  (union x-live* y-live* (remq lhs live*)))]
	       [(set! ,lhs (,binop ,[Triv -> x-live*] ,[Triv -> y-live*]))
		(guard (memq binop '(+ - * logand logor)))	
		(begin
		  (add-conflicts! ct lhs live*)
		  (union x-live* y-live* (remq lhs live*)))]
	       [(set! ,lhs ,var)
		(begin
		  (add-conflicts! ct lhs live*)
		  (if (or (uvar? var) (frame-var? var)) (set-cons var (remq lhs live*)) (remq lhs live*)))]
	       [(return-point ,rplab ,tail)
		(let ((new-live* (Tail tail ct)))
		  (set! call-live* (union call-live* live*))
		  (union live* new-live*))]
	       [,x (error who "invalid Effect list ~s" x)])))
    (define Pred
      (lambda (x t-live* f-live* ct)
        (match x
	       [(true) t-live* ]
	       [(false) f-live* ]
	       [(if ,test ,[c-live*] ,[a-live*]) 
		(union t-live* f-live* (Pred test c-live* a-live* ct))]
	       [(begin ,ef* ... ,[live*]) (Effect* ef* live* ct)]
	       [(,predop ,[Triv -> x-live*] ,[Triv -> y-live*])
		(remove-nulls (union x-live* y-live* t-live* f-live*))]
	       [,x (error who "invalid Pred ~s" x)])))
    (define Tail
      (lambda (x ct)
        (match x
	       [(begin ,ef* ... ,[live*]) (Effect* ef* live* ct)]
	       [(if ,test ,[c-live*] ,[a-live*]) (Pred test c-live* a-live* ct)]
	       [(,[Triv -> target] ,[Triv -> live*] ...) `(,target ... ,live* ... ...)]
	       [,x (error who "invalid Tail ~s" x)])))
    (match x
	   [(locals (,uvar* ...) (new-frames (,nfv** ...) ,tail))
	    (let ([ct (map (lambda (x) (cons x '())) uvar*)])
	      (let ([uvar* (filter uvar? (Tail tail ct))])
		(unless (null? uvar*)
			(error who "found variables ~s live on entry" uvar*)))
	      (let ([spill* (filter uvar? call-live*)])
		`(locals (,(difference uvar* spill*) ...)
			 (new-frames (,nfv** ...)
				     (spills ,spill*
					     (frame-conflict ,ct
							     (call-live (,call-live* ...) ,tail)))))))]
	   [,x (error who "invalid Body ~s" x)]))
  (lambda (x)
    (match x
	   [(letrec ([,label* (lambda () ,[Body -> body*])] ...) ,[Body -> body])
	    `(letrec ([,label* (lambda () ,body*)] ...) ,body)]
	   [,x (error who "invalid Program ~s" x)])))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

					;Simpler version of assign frame assigns a frame variable for all variables in the spill list, done through the find-homes function

(define-who pre-assign-frame
  (define find-used
    (lambda (conflict* home*)
      (cond
       [(null? conflict*) '()]
       [(frame-var? (car conflict*)) 
	(set-cons (car conflict*) (find-used (cdr conflict*) home*))]
       [(assq (car conflict*) home*) => 
	(lambda (x) (set-cons (cadr x) (find-used (cdr conflict*) home*)))]
       [else (find-used (cdr conflict*) home*)])))
  (define find-frame-var
    (lambda (used*)
      (let f ([index 0])
	(let ([fv (index->frame-var index)])
	  (if (memq fv used*) (f (+ index 1)) fv)))))
  (define find-homes
    (lambda (var* ct home*)
      (if (null? var*)
	  home*
	  (let ([var (car var*)] [var* (cdr var*)])
	    (let ([conflict* (cdr (assq var ct))])
	      (let ([home (find-frame-var (find-used conflict* home*))])
		(find-homes var* ct `((,var ,home) . ,home*))))))))
  (define Body
    (lambda (body)
      (match body
	     [(locals (,local* ...)
		      (new-frames (,nfv** ...)
				  (spills (,spill* ...)
					  (frame-conflict ,ct
							  (call-live (,call-live* ...) ,tail)))))
	      (let ([home* (find-homes spill* ct '())])
		`(locals (,local* ...)
			 (new-frames (,nfv** ...)
				     (locate (,home* ...)
					     (frame-conflict ,ct
							     (call-live (,call-live* ...) ,tail))))))]
	     [,body (error who "invalid Body ~s" body)])))
  (lambda (x)
    (match x
	   [(letrec ([,label* (lambda () ,[Body -> body*])] ...) ,[Body -> body])
	    `(letrec ([,label* (lambda () ,body*)] ...) ,body)]
	   [,x (error who "invalid Program ~s" x)])))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

;;;(return-point rp-label tail) =>
;;;  (begin
;;;    (set! fp (+ fp nb))
;;;    (return-point rp-label tail)
;;;    (set! fp (- fp nb)))

(define-who assign-new-frame
  (define Effect
    (lambda (fs)
      (lambda (x)
        (match x
	       [(nop) '(nop)]
	       [(if ,[(Pred fs) -> test] ,[(Effect fs) -> conseq] ,[(Effect fs) -> altern])
		`(if ,test ,conseq ,altern)]
	       [(begin ,[ef*] ... ,[ef]) 	(make-begin `(,ef* ... ,ef))]
	       [(mset! ,base ,offset ,value) `(mset! ,base ,offset ,value)]
	       [(set! ,lhs ,rhs) `(set! ,lhs ,rhs)]
	       [(return-point ,rplab ,[(Tail fs) -> tail])
		(make-begin
		 `((set! ,frame-pointer-register (+ ,frame-pointer-register ,(ash fs align-shift)))
		   ,x
		   (set! ,frame-pointer-register (- ,frame-pointer-register ,(ash fs align-shift)))))]
	       [,x (error who "invalid Effect ~s" x)]))))
  (define Pred
    (lambda (fs)
      (lambda (x)
        (match x
	       [(true) '(true)]
	       [(false) '(false)]
	       [(if ,[test] ,[conseq] ,[altern]) `(if ,test ,conseq ,altern)]
	       [(begin ,[(Effect fs) -> ef*] ... ,[pr])  (make-begin `(,ef* ... ,pr))]
	       [(,predop ,x ,y) `(,predop ,x ,y)]
	       [,x (error who "invalid Pred ~s" x)]))))
  (define Tail
    (lambda (fs)
      (lambda (x)
        (match x
	       [(if ,[(Pred fs) -> test] ,[(Tail fs) -> conseq] ,[ (Tail fs) -> altern])
		`(if ,test ,conseq ,altern)]
	       [(begin ,[(Effect fs) -> ef*] ... ,[(Tail fs) -> tail]) (make-begin `(,ef* ... ,tail))]
	       [(,triv ,live* ...) `(,triv ,live* ...)]
	       [,x (error who "invalid Tail ~s" x)]))))
  (define find-max					;;This function is used to determine the size of the frame used by the function
    (lambda (ls)
      (cond
       [(null? ls) '-1 ]
       [else (max (car ls) (find-max (cdr ls)))])))
	;;; The function argument to map does all the work we basically have to find the max-index of all call-live variables which can either be a frame variable
	;;; or we could look up the frame variable assigned to a uvar via the pre-assign frame pass
  (define Body
    (lambda (x)
      (define frame-size 
	(lambda (call-live* home*)
	  (let ([ls (map (lambda (x)
			   (if (frame-var? x) 
			       (frame-var->index x)
			       (frame-var->index (cadr (assq x home*))))) call-live*)])
	    (add1 (find-max ls)))))
      (match x
	     [(locals (,local* ...)
		      (new-frames (,nfv** ...)
				  (locate (,home* ...)
					  (frame-conflict ,ct
							  (call-live (,call-live* ...) ,tail)))))
	      (let ([fs (frame-size call-live* home*)])
		(define (do-assign var*)
		  (let f ([index fs] [ls var*] [rs '()])
		    (let ((fv (index->frame-var index)))
		      (cond
		       [(null? ls) rs]
		       [else (f (add1 index) (cdr ls) (cons `(,(car ls) ,fv) rs))]))))
		`(locals (,(difference local* `(,nfv** ... ...)) ...)
			 (ulocals ()
				  (locate (,home* ... ,(map do-assign nfv**) ... ...)
					  (frame-conflict ,ct ,((Tail fs) tail))))))]
	     [,x (error who "invalid Body ~s" x)])))
  (lambda (x)
    (match x
	   [(letrec ([,label* (lambda () ,[Body -> body*])] ...) ,[Body -> body])
	    `(letrec ([,label* (lambda () ,body*)] ...) ,body)]
	   [,x (error who "invalid Program ~s" x)])))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

;;; mrefs are still handled as binops here
;;; mset! clause added, if any of the parameters has been assigned as a frame it is reflected here

(define-who finalize-frame-locations
  (define Var
    (lambda (env)
      (lambda (v)
        (cond
	 [(and (uvar? v) (assq v env)) => cdr]
	 [else v]))))
  (define Triv Var)
  (define Pred
    (lambda (env)
      (lambda (pr)
        (match pr
	       [(true) '(true)]
	       [(false) '(false)]
	       [(if ,[test] ,[conseq] ,[altern]) `(if ,test ,conseq ,altern)]
	       [(begin ,[(Effect env) -> ef*] ... ,[pr]) `(begin ,ef* ... ,pr)]
	       [(,predop ,[(Triv env) -> x] ,[(Triv env) -> y]) `(,predop ,x ,y)]
	       [,pr (error who "invalid Pred ~s" pr)]))))
  (define Effect
    (lambda (env)
      (lambda (ef)
        (match ef
	       [(nop) '(nop)]
	       [(set! ,[(Var env) -> x]
		      (,binop ,[(Triv env) -> y] ,[(Triv env) -> z]))
		`(set! ,x (,binop ,y ,z))]
	       [(set! ,[(Var env) -> x] ,[(Triv env) -> y])
		(if (eq? y x) `(nop) `(set! ,x ,y))]
	       [(mset! ,[(Var env) -> base] ,[(Var env) -> offset] ,[(Var env) -> value]) `(mset! ,base ,offset ,value)]
	       [(begin ,[ef] ,[ef*] ...) `(begin ,ef ,ef* ...)]
	       [(if ,[(Pred env) -> test] ,[conseq] ,[altern])
		`(if ,test ,conseq ,altern)]
	       [(return-point ,rplab ,[(Tail env) -> tail]) ;;Handling return-point expressions in the Effect 
           	`(return-point ,rplab ,tail)]
	       [,ef (error who "invalid Effect ~s" ef)]))))
  (define Tail
    (lambda (env)
      (lambda (tail)
        (match tail
	       [(begin ,[(Effect env) -> ef*] ... ,[tail]) `(begin ,ef* ... ,tail)]
	       [(if ,[(Pred env) -> test] ,[conseq] ,[altern])
		`(if ,test ,conseq ,altern)]
	       [(,[(Triv env) -> t] ,[(Triv env) -> live*] ...) `(,t ,live* ...)]
	       [,tail (error who "invalid Tail ~s" tail)]))))
  (define Body
    (lambda (bd)
      (match bd
	     [(locals (,local* ...)
		      (ulocals (,ulocal* ...)
			       (locate ([,uvar* ,loc*] ...)
				       (frame-conflict ,ct ,[(Tail (map cons uvar* loc*)) -> tail]))))
	      `(locals (,local* ...)
		       (ulocals (,ulocal* ...)
				(locate ([,uvar* ,loc*] ...)
					(frame-conflict ,ct ,tail))))]
	     [(locate ([,uvar* ,loc*] ...) ,tail) 
	      `(locate ([,uvar* ,loc*] ...) ,tail)]
	     [,bd (error who "invalid Body ~s" bd)])))
  (lambda (x)
    (match x
	   [(letrec ([,label* (lambda () ,[Body -> bd*])] ...) ,[Body -> bd])
	    `(letrec ([,label* (lambda () ,bd*)] ...) ,bd)]
	   [,x (error who "invalid Program ~s" x)])))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

;;; Select instructions requires mrefs and msets to be rewritten substantially in some cases
;;; I prepared a table based on base and offset values
;;;offset		base  ----------->
;;;|					ur	int32	 fvar  label  
;;;|	ur			X1  X1      X3    X3
;;;| int32   X4  X2      X5    X5
;;;| fvar    X6  X2      X5    X5
;;;| label   X6  X2      X5    X5
;;;|
;;;v

;;;X1 => return expression as is
;;;X2 => (set! u base) (set! lhs (mref u offset))
;;;X3 => (set! u offset) (set! lhs (mref base u))
;;;X4 => (set! lhs (mref offset base))
;;;X5 => (set! u1 base) (set! u2 offset) (set! lhs (mref u1 u2))
;;;X6 => first do X4 and then X3

;;; This pretty much handles all cases that there are, mrefs and mset! are handled in the same way

(define-who select-instructions
  (define (ur? x) (or (register? x) (uvar? x)))
  (define (Body x)
    (define new-ulocal* '())
    (define int64-or-label?
      (lambda (x) (or (and (not (int32? x)) (int64? x)) (label? x))))
    (define (new-u)
      (let ([u (unique-name 't)])
        (set! new-ulocal* (cons u new-ulocal*))
        u))
    (define (select-binop-1 var binop triv1 triv2)
      (cond
       [(eq? var triv1) (select-binop-2 binop var triv2)]
       [(and (eq? var triv2) (member binop '(+ * logor logand))) (select-binop-2 binop var triv1)]
       [else (let ([u (new-u)])
	       `(begin (set! ,u ,triv1) ,(select-binop-2 binop u triv2) (set! ,var ,u)))]))
    (define (select-binop-2 binop var triv) 
      (cond
       [(and (member binop '(- + sra logor logand))
	     (or (int64-or-label? triv) (and (frame-var? var) (frame-var? triv))))
	(let ([u (new-u)])
	  `(begin (set! ,u ,triv) (set! ,var (,binop ,var ,u))))]
        ;;; X2
       [(and (eq? binop '*) (frame-var? var))
	(let ([u (new-u)])
	  `(begin (set! ,u ,var) ,(select-binop-2 binop u triv) (set! ,var ,u)))]
        ;;; X1 for *
       [(and (eq? binop '*) (ur? var) (int64-or-label? triv))
	(let ([u (new-u)])
	  `(begin (set! ,u ,triv) (set! ,var (,binop ,var ,u))))]
       [else `(set! ,var (,binop ,var ,triv))]))
    (define (select-move var triv)
      (if (and (frame-var? var) (or (frame-var? triv) (int64-or-label? triv)))
			            ;;; X0
	  (let ([u (new-u)])
	    `(begin (set! ,u ,triv) (set! ,var ,u)))
	  `(set! ,var ,triv)))
    (define select-relop 
      (lambda (relop x y)
	(cond
	 [(and (int32? x) (or (ur? y) (frame-var? y))) `(,(relop^ relop) ,y ,x)]
	 [(or (and (frame-var? x) (frame-var? y))
	      (and (int32? x) (int32? y))
	      (and (int64-or-label? x) (or (ur? y) (frame-var? y) (int32? y))))
	  (let ([u (new-u)])
	    `(begin (set! ,u ,x) (,relop ,u ,y)))]
	 [(and (or (ur? x) (frame-var? x) (int32? x))
	       (int64-or-label? y))
	  (let ([u (new-u)])
	    `(begin (set! ,u ,y) (,(relop^ relop) ,u ,x)))]
	 [(and (int64-or-label? x) (int64-or-label? y))
	  (let ([u1 (new-u)] [u2 (new-u)])
	    `(begin (set! ,u1 ,x) (set! ,u2 ,y) (,relop ,u1 ,u2)))]
	 [else `(,relop ,x ,y)])))
		;;;select mref and mset do the same thing the only difference being that the former returns mref expressions and the latter returns mset!
    (define select-mref
      (lambda (lhs base offset)
	(cond
	 [(or (and (ur? base) (integer? offset))
	      (and (ur? base) (ur? offset))) `((set! ,lhs (mref ,base ,offset)))]	;;X1
	 [(and (integer? offset) (or (integer? base) (frame-var? base) (label? base)))
	  (let ((u (new-u)))
	    `((set! ,u ,base) (set! ,lhs (mref ,u ,offset))))]									;;X2
	 [(and (ur? base) (or (frame-var? offset) (label? offset)))
	  (let ((u (new-u)))
	    `((set! ,u ,offset) (set! ,lhs (mref ,base ,u))))]
	 [(and (ur? offset) (or (frame-var? base) (frame-var? offset)))
	  (select-mref lhs offset base)]
	 [else (let ((u1 (new-u)) (u2 (new-u)))
		 `((set! ,u1 ,base) (set! ,u2 ,offset) (set! ,lhs (mref ,u1 ,u2))))])))
    (define select-mset
      (lambda (base offset value)
	(cond
	 [(or (and (ur? base) (integer? offset))
	      (and (ur? base) (ur? offset))) `((mset! ,base ,offset ,value))]
	 [(and (integer? offset) (or (integer? base) (frame-var? base) (label? base)))
	  (let ((u (new-u)))
	    `((set! ,u ,base) (mset! ,u ,offset ,value) (set! ,base ,u)))]
	 [(and (ur? base) (or (frame-var? offset) (label? offset)))
	  (let ((u (new-u)))
	    `((set! ,u ,offset) (mset! ,base ,u ,value)))]
	 [(and (ur? offset) (or (frame-var? base) (frame-var? offset)))
	  (select-mset offset base value)]
	 [else (let ((u1 (new-u)) (u2 (new-u)))
		 `((set! ,u1 ,base) (set! ,u2 ,offset) (mset! ,u1 ,u2 ,value)))])))
    (define Effect 
      (lambda (ef)
	(match ef
	       [(nop) '(nop)]
	       [(begin ,[Effect -> ef*] ... ,[Effect -> ef]) (make-begin `(,ef* ... ,ef))]
	       [(if ,[Pred -> test] ,[Effect -> conseq] ,[Effect -> altern]) `(if ,test ,conseq ,altern)]
	       [(set! ,lhs (mref ,base ,offset))
		(cond
		 [(and (integer? base) (ur? offset)) (make-begin (select-mref lhs offset base))] ;;exchange base and offset
		 [(ur? lhs) (make-begin (select-mref lhs base offset))] ;;;pass lhs as it is
		 [(frame-var? lhs)
		  (let ((u (new-u)))
		    (make-begin `((set! ,u ,lhs) ,(select-mref u base offset) ... (set! ,lhs ,u))))] ;;;if frame-var assign a new unspillable and assign it back
		 [(label? lhs) 					
		  (let ((u (new-u)))
		    (make-begin `((set! ,u ,lhs) ,(select-mref u base offset) ...)))] ;;;if lhs a label assign new unspillable and call select-mref passing new lhs
		 [else '(nop)])]
	       [(set! ,lhs (,binop ,x ,y)) (select-binop-1 lhs binop x y)]
	       [(set! ,lhs ,rhs) (select-move lhs rhs)]
	       [(mset! ,base ,offset ,value)
		(cond 
		 [(and (integer? base) (ur? offset)) (make-begin (select-mset offset base value))]
		 [(or (ur? value) (integer? value)) (make-begin (select-mset base offset value))]
		 [(frame-var? value)
		  (let ((u (new-u)))
		    (make-begin `((set! ,u ,value) ,(select-mset base offset u) ... (set! ,value ,u))))]
		 [(label? value)
		  (let ((u (new-u)))
		    (make-begin `((set! ,u ,value) ,(select-mset base offset u) ...)))])]
	       [(return-point ,rplab ,[Tail -> tail]) `(return-point ,rplab ,tail)] ;;;Process tail and send the rest of instructions as is
	       [,x (error who "invalid Effect ~s" x)])))
    (define (Pred x) 
      (match x
	     [(true) '(true)]
	     [(false) '(false)]
	     [(if ,[Pred -> pred] ,[Pred -> conseq] ,[Pred -> alt])
	      `(if ,pred ,conseq ,alt)]
	     [(begin ,[Effect -> ef*] ...,[Pred -> tail]) 
	      (make-begin `(,ef* ... ,tail))]
	     [(,relop ,conseq ,alt) (select-relop relop conseq alt)]))
    (define (Tail x)
      (match x
	     [(begin ,[Effect -> ef*] ... ,[Tail -> tail])
	      (make-begin `(,ef* ... ,tail))]
	     [(if ,[Pred -> pred] ,[Tail -> conseq] ,[Tail -> alt]) 
	      `(if ,pred ,conseq ,alt)]
	     [(,loc* ...) `(,loc* ...)]))
    (match x
	   [(locals (,local* ...) 
		    (ulocals (,ulocal* ...)
			     (locate (,home* ...) (frame-conflict ,ct ,[Tail -> tail]))))
	    `(locals (,local* ...)
		     (ulocals (,ulocal* ... ,new-ulocal* ...)
			      (locate (,home* ...)
				      (frame-conflict ,ct ,tail))))]
	   [(locate (,home* ...) ,tail) `(locate (,home* ...) ,tail)]
	   [,x (error who "invalid Body ~s" x)]))
  (lambda (x)
    (match x
	   [(letrec ([,label* (lambda () ,[Body -> body*])] ...) ,[Body -> body])
	    `(letrec ([,label* (lambda () ,body*)] ...) ,body)]
	   [,x (error who "invalid Program ~s" x)])))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

;;;uncover register conflicts needs to handle mrefs and mset's in different way while updating the conflict table
;;;(set! x (mref base offset)) => will mean that x conflicts with both base and offset and hence we must record these conflicts
;;;(mset! base offset value) => in this we have to record the conflicts of each parameters with the other 

(define-who uncover-register-conflict
  (define add-conflicts!
    (lambda (ct lhs live*)
      (define add-conflict!
	(lambda (var1 var2)
	  (let ([a (assq var1 ct)])
	    (set-cdr! a (if (eq? var1 var2) (cdr a)  (set-cons var2 (cdr a)))))))
      (when (uvar? lhs)
	    (for-each
	     (lambda (live) (add-conflict! lhs live))
	     live*))
      (for-each
       (lambda (live) (when (and (uvar? live) (not (frame-var? lhs))) (add-conflict! live lhs)))
       live*)))
  (define Triv (lambda (x) (if (or (uvar? x) (register? x)) `(,x) '())))
  (define Effect*
    (lambda (x live* ct)
      (match x
	     [() live*]
	     [(,ef* ... ,ef) (Effect* ef* (Effect ef live* ct) ct)]
	     [,x (error who "invalid Effect* list ~s" x)])))
  (define Effect
    (lambda (x live* ct)
      (match x
	     [(nop) live*]
	     [(if ,test ,[c-live*] ,[a-live*]) 
	      (Pred test  c-live* a-live* ct)]
	     [(mset! ,[Triv -> base] ,[Triv -> offset] ,[Triv -> value])
	      (begin
		(if (not (null? base)) (add-conflicts! ct (car base) (union offset value live*)))
		(if (not (null? offset)) (add-conflicts! ct (car offset) (union base value live*)))
		(if (not (null? value)) (add-conflicts! ct (car value) (union base offset live*)))
		(union base offset value live*))]
	     [(begin ,ef* ... ,[live*]) (Effect* ef* live* ct)]
	     [(set! ,lhs (mref ,[Triv -> x-live*] ,[Triv -> y-live*]))
	      (begin
		(add-conflicts! ct lhs (union x-live* y-live* live*))
		(union x-live* y-live* (remq lhs live*)))]
	     [(set! ,lhs (,binop ,[Triv -> x-live*] ,[Triv -> y-live*]))
	      (begin
		(add-conflicts! ct lhs live*)
		(union x-live* y-live* (remq lhs live*)))]
	     [(set! ,lhs ,var)
	      (begin
		(add-conflicts! ct lhs live*)
		(if (or (uvar? var) (register? var)) (set-cons var (remq lhs live*)) (remq lhs live*)))]
					; ignoring incoming live*, since it should not contain anything
					; but caller-save registers, which the call kills (see note in
					; the assignment description)
	     [(return-point ,rplab ,tail) (Tail tail ct)] ;;;Return the list of variables live in the tail ignoring the variables that were live before the call was made
	     [,x (error who "invalid Effect list ~s" x)])))
  (define Pred
    (lambda (x t-live* f-live* ct)
      (match x
	     [(true) t-live* ]
	     [(false) f-live* ]
	     [(if ,test ,[c-live*] ,[a-live*]) (union t-live* f-live* (Pred test c-live* a-live* ct))]
	     [(begin ,ef* ... ,[live*]) (Effect* ef* live* ct)]
	     [(,predop ,[Triv -> x-live*] ,[Triv -> y-live*])
	      (union x-live* y-live* t-live* f-live*)]
	     [,x (error who "invalid Pred ~s" x)])))
  (define Tail
    (lambda (x ct)
      (match x
	     [(begin ,ef* ... ,[live*]) (Effect* ef* live* ct)]
	     [(if ,test ,[c-live*] ,[a-live*]) (Pred test c-live* a-live* ct)]
	     [(,[Triv -> target-live*] ,[Triv -> live*] ...) `(,target-live* ... ,live* ... ...)]
	     [,x (error who "invalid Tail ~s" x)])))
  (define Body
    (lambda (x)
      (match x
	     [(locals (,local* ...) 
		      (ulocals (,ulocal* ...)
			       (locate (,home* ...)
				       (frame-conflict ,fv-ct ,tail))))
	      (let ([ct (map (lambda (x) (cons x '())) `(,local* ... ,ulocal* ...))])
		(let ([uvar* (filter uvar? (Tail tail ct))])
		  (unless (null? uvar*)
			  (error who "found variables ~s live on entry" uvar*)))
		`(locals (,local* ...) 
			 (ulocals (,ulocal* ...)
				  (locate (,home* ...)
					  (frame-conflict ,fv-ct
							  (register-conflict ,ct ,tail))))))]
	     [(locate (,home* ...) ,tail) `(locate (,home* ...) ,tail)]
	     [,x (error who "invalid Body ~s" x)])))
  (lambda (x)
    (match x
	   [(letrec ([,label* (lambda () ,[Body -> body*])] ...) ,[Body -> body])
	    `(letrec ([,label* (lambda () ,body*)] ...) ,body)]
	   [,x (error who "invalid Program ~s" x)])))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

;;assigns register to the uvars made a chnage documented below

(define-who assign-registers
  (define remove-occurence						;;Removes the occurence of a var from var* and returns the list
    (lambda (var ct)
      (map (lambda (x) 
	     (cond
	      [(eq? (car x) var) x]
	      [else (remq var x)])) ct)))
  (define replace																		;;Replaces the occurences of variables in the conflict-list with the register-homes
    (lambda (allocations ct)
      (cond 
       [(null? allocations) ct]
       [else (replace (cdr allocations) (replace-helper (car allocations) ct))])))
  (define replace-helper
    (lambda (allocation ct)
      (map (lambda (ct-entry)
	     (cond
	      [(eq? (car allocation) (car ct-entry)) allocation]
	      [else (cons (car ct-entry) (replace* (cdr ct-entry) allocation))])) ct)))
  (define replace*
    (lambda (conflicts allocation)
      (cond
       [(null? conflicts) '()]
       [(eq? (car conflicts) (car allocation)) (cons (cadr allocation) (replace* (cdr conflicts) allocation))]
       [else (cons (car conflicts) (replace* (cdr conflicts) allocation))])))			
  (define k (length registers))
  (define low-degree?
    (lambda (var ct)
      (< (length (cdr (assq var ct))) k)))
  (define num-conflicts
    (lambda (var ct)
      (let ((temp (assq var ct)))
	(if (null? temp) 2000 (length (cdr (assq var ct)))))))
  (define pick-min																										;;Picks a node with least number of conflicts like the min function
    (lambda (var degree var* ct)
      (cond
       [(null? var) 'xxx]
       [(null? var*) var]
       [(<= degree (num-conflicts (car var*) ct)) (pick-min var degree (cdr var*) ct)]
       [else (let* ((node (car var*))
		    (degree^ (num-conflicts node ct)))
	       (pick-min node degree^ (cdr var*) ct))])))
  (define assign-null
    (lambda (ls)
      (if (null? ls) 'xxx (car ls))))
	;;;altered the function here as advised by Andy Keep 
	;;;first I will assign all the variables in spillable list and then on the unspillable list
  (define find-homes
    (lambda (spillable* unspillable* ct)
      (cond
       [(and (null? spillable*) (null? unspillable*)) '()]
       [(null? spillable*) (find-homes unspillable* '() ct)]
       [else (let* ((current-var (pick-min (car spillable*) (num-conflicts (car spillable*) ct) (cdr spillable*) ct))
		    (new-conflict-table (remove-occurence current-var ct))
		    (results (find-homes (remq current-var spillable*) (remq current-var unspillable*) new-conflict-table))
		    (updated-ct (replace results ct))
		    (conflict-entry (cdr (assq current-var updated-ct)))
		    (remaining-registers (difference registers conflict-entry)))
	       (if (null? remaining-registers) 
		   results 
		   (let ((assign-register (car remaining-registers)))
		     (cons (list current-var assign-register) results))))])))
  (define get-replacement
    (lambda (var entry)
      (list var (car (difference registers entry)))))
  (define Body
    (lambda (x)
      (match x
	     [(locals (,local* ...) 
		      (ulocals (,ulocal* ...)
			       (locate (,frame-home* ...)
				       (frame-conflict ,fv-ct
						       (register-conflict ,ct ,tail)))))
	      ;; putting local* before ulocal* allows find-homes to choose the
	      ;; first element of the list when all variables are high degree and
	      ;; be guaranteed a spillable variable if one is left.  if find-homes
	      ;; wants to be more clever about choosing a high-degree victim, it
	      ;; will have to be told which variables are spillable.
	      (let ([uvar* (append local* ulocal*)])
		(let ([home* (find-homes local* ulocal* ct)])
		  (let ([spill* (difference uvar* (map car home*))])
		    (cond
		     [(null? spill*) `(locate (,frame-home* ... ,home* ...) ,tail)]
		     [(null? (intersection ulocal* spill*))
		      (let ([local* (difference local* spill*)])
			`(locals (,local* ...)
				 (ulocals (,ulocal* ...)
					  (spills (,spill* ...)
						  (locate (,frame-home* ...)
							  (frame-conflict ,fv-ct ,tail))))))]
		     [else 
		      (error who "unspillable variables (~s) have been spilled"
			     (difference spill* local*))]))))]
	     [(locate (,home* ...) ,tail) `(locate (,home* ...) ,tail)]
	     [,x (error who "invalid Body ~s" x)])))
  (lambda (x)
    (match x
	   [(letrec ([,label* (lambda () ,[Body -> body*])] ...) ,[Body -> body])
	    `(letrec ([,label* (lambda () ,body*)] ...) ,body)]
	   [,x (error who "invalid Program ~s" x)])))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

(define-who everybody-home?
  (define all-home?
    (lambda (body)
      (match body
	     [(locals (,local* ...)
		      (ulocals (,ulocal* ...)
			       (spills (,spill* ...)
				       (locate (,home* ...)
					       (frame-conflict ,ct ,tail))))) #f]
	     [(locate (,home* ...) ,tail) #t]
	     [,x (error who "invalid Body ~s" x)])))
  (lambda (x)
    (match x
	   [(letrec ([,label* (lambda () ,body*)] ...) ,body)
	    (andmap all-home? `(,body ,body* ...))]
	   [,x (error who "invalid Program ~s" x)])))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

;;;pass changed since last assignment

(define-who assign-frame
  (define find-used
    (lambda (conflict* home*)
      (cond
       [(null? conflict*) '()]
       [(frame-var? (car conflict*)) 
	(set-cons (car conflict*) (find-used (cdr conflict*) home*))]
       [(assq (car conflict*) home*) => 
	(lambda (x) (set-cons (cadr x) (find-used (cdr conflict*) home*)))]
       [else (find-used (cdr conflict*) home*)])))
  (define find-frame-var
    (lambda (used*)
      (let f ([index 0])
        (let ([fv (index->frame-var index)])
          (if (memq fv used*) (f (+ index 1)) fv)))))
  (define find-homes
    (lambda (var* ct home*)
      (if (null? var*)
          home*
          (let ([var (car var*)] [var* (cdr var*)])
            (let ([conflict* (cdr (assq var ct))])
              (let ([home (find-frame-var (find-used conflict* home*))])
                (find-homes var* ct `((,var ,home) . ,home*))))))))
  (define Body
    (lambda (body)
      (match body
	     [(locals (,local* ...)
		      (ulocals (,ulocal* ...)
			       (spills (,spill* ...)
				       (locate (,home* ...)
					       (frame-conflict ,ct ,tail)))))
	      (let ([home* (find-homes spill* ct home*)])
		`(locals (,local* ...)
			 (ulocals (,ulocal* ...)
				  (locate (,home* ...)
					  (frame-conflict ,ct ,tail)))))]
	     [(locate (,home* ...) ,body) `(locate (,home* ...) ,body)]
	     [,body (error who "invalid Body ~s" body)])))
  (lambda (x)
    (match x
	   [(letrec ([,label* (lambda () ,[Body -> body*])] ...) ,[Body -> body])
	    `(letrec ([,label* (lambda () ,body*)] ...) ,body)]
	   [,x (error who "invalid Program ~s" x)])))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

;;; mref and mset! are allowed to go as they are, as they are not affected by what this pass does

(define-who discard-call-live
  (define Tail
    (lambda (tail)
      (match tail
	     [(begin ,[Effect -> ef*] ... ,[tail]) `(begin ,ef* ... ,tail)]
	     [(if ,[Pred -> test] ,[conseq] ,[altern]) `(if ,test ,conseq ,altern)]
	     [(,t ,live* ...) `(,t)]
	     [,tail (error who "invalid Tail ~s" tail)])))
  (define Pred
    (lambda (pr)
      (match pr
	     [(true) '(true)]
	     [(false) '(false)]
	     [(if ,[test] ,[conseq] ,[altern]) `(if ,test ,conseq ,altern)]
	     [(begin ,[Effect -> ef*] ... ,[pr]) `(begin ,ef* ... ,pr)]
	     [(,predop ,x ,y) `(,predop ,x ,y)]
	     [,pr (error who "invalid Pred ~s" pr)])))
  (define Effect
    (lambda (ef)
      (match ef
	     [(nop) '(nop)]
	     [(set! ,x ,rhs) `(set! ,x ,rhs)]
	     [(mset! ,base ,offset ,value) ef]
	     [(begin ,[ef*] ... ,[ef]) `(begin ,ef* ... ,ef)]
	     [(if ,[Pred -> test] ,[conseq] ,[altern]) `(if ,test ,conseq ,altern)]
	     [(return-point ,rplab ,[Tail -> tail]) `(return-point ,rplab ,tail)]
	     [,ef (error who "invalid Effect ~s" ef)])))
  (define Body
    (lambda (bd)
      (match bd
	     [(locate ([,uvar* ,loc*] ...) ,[Tail -> tail])
	      `(locate ([,uvar* ,loc*] ...) ,tail)]
	     [,bd (error who "invalid Body ~s" bd)])))
  (lambda (x)
    (match x
	   [(letrec ([,label* (lambda () ,[Body -> bd*])] ...) ,[Body -> bd])
	    `(letrec ([,label* (lambda () ,bd*)] ...) ,bd)]
	   [,x (error who "invalid Program ~s" x)])))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

;;;finalize locations adds clauses for this weeks grammars and handles the mset! and mref clauses...If any of the arguments are assigned a frame-var
;;; or register it is assigned here

(define-who finalize-locations
  (define Var
    (lambda (env)
      (lambda (v)
        (if (uvar? v) (cdr (assq v env)) v))))
  (define Triv
    (lambda (env)
      (lambda (t)
        (if (uvar? t) (cdr (assq t env)) t))))
  (define Pred
    (lambda (env)
      (lambda (pr)
        (match pr
	       [(true) '(true)]
	       [(false) '(false)]
	       [(if ,[test] ,[conseq] ,[altern]) `(if ,test ,conseq ,altern)]
	       [(begin ,[(Effect env) -> ef*] ... ,[pr]) `(begin ,ef* ... ,pr)]
	       [(,predop ,[(Triv env) -> x] ,[(Triv env) -> y]) `(,predop ,x ,y)]
	       [,pr (error who "invalid Pred ~s" pr)]))))
  (define Effect
    (lambda (env)
      (lambda (ef)
        (match ef
	       [(nop) '(nop)]
	       [(set! ,[(Var env) -> x]
		      (,binop ,[(Triv env) -> y] ,[(Triv env) -> z]))
		`(set! ,x (,binop ,y ,z))]
	       [(set! ,[(Var env) -> x] ,[(Triv env) -> y]) 
		(if (eq? y x) `(nop) `(set! ,x ,y))]
	       [(mset! ,[(Var env) -> base] ,[(Var env) -> offset] ,[(Var env) -> val])
		`(mset! ,base ,offset ,val)]
	       [(begin ,[ef] ,[ef*] ...) `(begin ,ef ,ef* ...)]
	       [(if ,[(Pred env) -> test] ,[conseq] ,[altern])
		`(if ,test ,conseq ,altern)]
	       [(return-point ,rplab ,[(Tail env) -> tail])
           	`(return-point ,rplab ,tail)]
	       [,ef (error who "invalid Effect ~s" ef)]))))
  (define Tail
    (lambda (env)
      (lambda (tail)
        (match tail
	       [(begin ,[(Effect env) -> ef*] ... ,[tail]) `(begin ,ef* ... ,tail)]
	       [(if ,[(Pred env) -> test] ,[conseq] ,[altern])
		`(if ,test ,conseq ,altern)]
	       [(,[(Triv env) -> t]) `(,t)]
	       [,tail (error who "invalid Tail ~s" tail)]))))
  (define Body
    (lambda (bd)
      (match bd
	     [(locate ([,uvar* ,loc*] ...) ,tail) ((Tail (map cons uvar* loc*)) tail)]
	     [,bd (error who "invalid Body ~s" bd)])))
  (lambda (x)
    (match x
	   [(letrec ([,label* (lambda () ,[Body -> bd*])] ...) ,[Body -> bd])
	    `(letrec ([,label* (lambda () ,bd*)] ...) ,bd)]
	   [,x (error who "invalid Program ~s" x)])))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

;;The triv function checks to see if a frame var has been encountered and accordingly makes the displacement operand
;; To each function we pass the offset on return from a tail expression offset must be set to zero
;;; Finally we get rid of the mref and mset! expressions here
;;; (mset! x y z) means x[y] = z 
;;; if x is assigned a register and y a int then I make a displacement operand
;;; if x and y are assigned registers then I make an index operands
;;; otherwise I simply swap x and y and make a displacement operand ditto while handling the mrefs 
;;; otherwise the pass remains identical to last weeks pass

(define-who expose-frame-var
  (define Triv
    (lambda (fp-offset)
      (lambda (t)
        (if (frame-var? t)
            (make-disp-opnd frame-pointer-register
			    (- (ash (frame-var->index t) align-shift) fp-offset))
            t))))
  (define Pred
    (lambda (pr fp-offset)
      (match pr
	     [(true) (values '(true) fp-offset)]
	     [(false) (values '(false) fp-offset)]
	     [(begin ,ef* ... ,pr)
	      (let-values ([(ef* fp-offset) (Effect* ef* fp-offset)])
		(let-values ([(pr fp-offset) (Pred pr fp-offset)])
		  (values (make-begin `(,ef* ... ,pr)) fp-offset)))]
	     [(if ,test ,conseq ,altern)
	      (let-values ([(test fp-offset) (Pred test fp-offset)])
		(let-values ([(conseq c-fp-offset) (Pred conseq fp-offset)]
			     [(altern a-fp-offset) (Pred altern fp-offset)])
		  (values `(if ,test ,conseq ,altern) c-fp-offset)))]
	     [(,predop ,[(Triv fp-offset) -> tr1] ,[(Triv fp-offset) -> tr2])
	      (values `(,predop ,tr1 ,tr2) fp-offset)]
	     [,pr (error who "invalid Pred ~s" pr)])))
  (define Effect*
    (lambda (ef* fp-offset)
      (if (null? ef*)
          (values '() fp-offset)
          (let-values ([(ef fp-offset) (Effect (car ef*) fp-offset)])
            (let-values ([(ef* fp-offset) (Effect* (cdr ef*) fp-offset)])
              (values (cons ef ef*) fp-offset))))))
  (define Effect
    (lambda (st fp-offset)
      (match st
	     [(nop) (values '(nop) fp-offset)]
	     [(mset! ,[(Triv fp-offset) -> base] ,[(Triv fp-offset) -> offset] ,[(Triv fp-offset) -> value])
	      (cond
	       [(and (int32? base) (register? offset)) (values `(set! ,(make-disp-opnd offset base) ,value) fp-offset)]
	       [(and (int32? offset) (register? base)) (values `(set! ,(make-disp-opnd base offset) ,value) fp-offset)]
	       [else (values `(set! ,(make-index-opnd base offset) ,value) fp-offset)])]
	     [(set! ,fp (+ ,fp ,n))
	      (guard (eq? fp frame-pointer-register))
	      (values st (+ fp-offset n))]  ;;send the new offset as incoming offset + n
	     [(set! ,fp (- ,fp ,n))
	      (guard (eq? fp frame-pointer-register))
	      (values st (- fp-offset n))] 	;;send the new offset as incoming offset - n
	     [	(set! ,[(Triv fp-offset) -> var]
		      (mref ,[(Triv fp-offset) -> t1] ,[(Triv fp-offset) -> t2]))
		(cond
		 [(and (register? t1) (register? t2)) (values `(set! ,var ,(make-index-opnd t1 t2)) fp-offset)]
		 [(and (register? t1) (int32? t2)) (values `(set! ,var ,(make-disp-opnd t1 t2)) fp-offset)]
		 [(and (int32? t1) (register? t2)) (values `(set! ,var ,(make-disp-opnd t2 t1)) fp-offset)])]
	     [(set! ,[(Triv fp-offset) -> var]
		    (,binop ,[(Triv fp-offset) -> t1] ,[(Triv fp-offset) -> t2]))
	      (values `(set! ,var (,binop ,t1 ,t2)) fp-offset)]
	     [(set! ,[(Triv fp-offset) -> var] ,[(Triv fp-offset) -> t])
	      (values `(set! ,var ,t) fp-offset)]
	     [(begin ,ef* ... ,ef)
	      (let-values ([(ef* fp-offset) (Effect* ef* fp-offset)])
		(let-values ([(ef fp-offset) (Effect ef fp-offset)])
		  (values (make-begin `(,ef* ... ,ef)) fp-offset)))]
	     [(if ,test ,conseq ,altern)
	      (let-values ([(test fp-offset) (Pred test fp-offset)])
		(let-values ([(conseq c-fp-offset) (Effect conseq fp-offset)]
			     [(altern a-fp-offset) (Effect altern fp-offset)])
		  (values `(if ,test ,conseq ,altern) c-fp-offset)))]
	     [(return-point ,rplab ,[(Tail fp-offset) -> tail fp-offset])			;; Process the tail expression, get the same offset and return it
	      (values `(return-point ,rplab ,tail) fp-offset)]
	     [,st (error who "invalid syntax for Effect ~s" st)])))
  (define Tail
    (lambda (fp-offset)
      (lambda (tail)
        (match tail
	       [(begin ,ef* ... ,tail)
		(let-values ([(ef* fp-offset) (Effect* ef* fp-offset)])
		  (let-values ([(tl fp-offset) ((Tail fp-offset) tail)])
		    (values (make-begin `(,ef* ... ,tl)) fp-offset)))]
	       [(if ,test ,conseq ,altern)
          	(let-values ([(test fp-offset) (Pred test fp-offset)])
		  (let-values ([(conseq c-fp-offset) ((Tail fp-offset) conseq)]
			       [(altern a-fp-offset) ((Tail fp-offset) altern)])
		    (values `(if ,test ,conseq ,altern) c-fp-offset)))]
	       [(,[(Triv fp-offset) -> t]) (values `(,t) fp-offset)]
	       [,tail (error who "invalid syntax for Tail ~s" tail)]))))
  (define Body
    (lambda (x)
      (let-values ([(x fp-offset) ((Tail 0) x)])
        (unless (= fp-offset 0)
		(error who "nonzero final fp-offset ~s" fp-offset))
        x)))
  (lambda (program)
    (match program
	   [(letrec ([,label* (lambda () ,[Body -> body*])] ...) ,[Body -> body])
	    `(letrec ([,label* (lambda () ,body*)] ...) ,body)]
	   [,program (error who "invalid syntax for Program: ~s" program)])))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

;;; Doesnot change from previous assignment

(define-who expose-basic-blocks
  (define Tail
    (lambda (x)
      (match x
	     [(if ,pred ,[conseq cb*] ,[altern ab*])
	      (let ([clab (unique-label 'c)] [alab (unique-label 'a)])
		(let-values ([(tail xb*) (Pred pred clab alab)])
		  (values tail
			  `(,xb* ...
				 [,clab (lambda () ,conseq)]
				 [,alab (lambda () ,altern)]
				 ,cb* ...
				 ,ab* ...))))]
	     [(begin ,effect* ... ,[tail tb*])
	      (let-values ([(expr eb*) (Effect* effect* `(,tail))])
		(values expr `(,eb* ... ,tb* ...)))]
	     [(,triv) (values `(,triv) '())]
	     [,x (error who "invalid Tail ~s" x)])))
  (define (Pred x tlab flab)
    (match x
	   [(true) (values `(,tlab) '())]
	   [(false) (values `(,flab) '())]
	   [(if ,pred ,[conseq cb*] ,[altern ab*])
	    (let ([clab (unique-label 'c)] [alab (unique-label 'a)])
	      (let-values ([(expr xb*) (Pred pred clab alab)])
		(values expr
			`(,xb* ...
			       [,clab (lambda () ,conseq)]
			       [,alab (lambda () ,altern)]
			       ,cb* ...
			       ,ab* ...))))]
	   [(begin ,effect* ... ,[expr xb*])
	    (let-values ([(expr eb*) (Effect* effect* `(,expr))])
	      (values expr `(,eb* ... ,xb* ...)))]
	   [(,relop ,triv1 ,triv2)
	    (values `(if (,relop ,triv1 ,triv2) (,tlab) (,flab)) '())]
	   [,x (error who "invalid Tail ~s" x)]))
  (define (Effect* x* rest*)
    (match x*
	   [() (values (make-begin rest*) '())]
	   [(,x* ... ,x) (Effect x* x rest*)]))
  (define Effect 
    (lambda (x* x rest*)
      (match x
	     [(nop) (Effect* x* rest*)]
	     [(set! ,lhs ,rhs) (Effect* x* `((set! ,lhs ,rhs) ,rest* ...))]
	     [(if ,pred ,conseq ,altern)
	      (let ([clab (unique-label 'c)]
		    [alab (unique-label 'a)]
		    [jlab (unique-label 'j)])
		(let-values ([(conseq cb*) (Effect '() conseq `((,jlab)))]
			     [(altern ab*) (Effect '() altern `((,jlab)))]
			     [(expr xb*) (Pred pred clab alab)])
		  (let-values ([(expr eb*) (Effect* x* `(,expr))])
		    (values expr
			    `(,eb* ...
				   ,xb* ...
				   [,clab (lambda () ,conseq)]
				   [,alab (lambda () ,altern)]
				   [,jlab (lambda () ,(make-begin rest*))]
				   ,cb* ...
				   ,ab* ...)))))]
	     [(begin ,effect* ...) (Effect* `(,x* ... ,effect* ...) rest*)]
	     [(return-point ,rplab ,tail)
	      (let*-values ([(tail tail-label*) (Tail tail)] [(ef* ef-label*) (Effect* x* (cdr tail))])
		(values (make-begin `(,ef*))
			`(,ef-label* ... ,tail-label* ... [,rplab (lambda () ,(make-begin rest*))])))]
	     [,x (error who "invalid Effect ~s" x)])))
  (lambda (x)
    (match x
	   [(letrec ([,label* (lambda () ,[Tail -> tail* b**])] ...) ,[Tail -> tail b*])
	    `(letrec ([,label* (lambda () ,tail*)] ... ,b** ... ... ,b* ...) ,tail)]
	   [,x (error who "invalid Program ~s" x)])))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

;;; Doesnot change from previous assignment

(define flatten-program
  (lambda (prog)
    (define build-exp
      (lambda (label* tail*)
	(match label*
	       [() '()]
	       [(,current ,rest* ...)
		(let ((current-exp (append (list current) (Tail rest* (car tail*)))))
		  (append current-exp (build-exp rest* (cdr tail*))))])))
    (define Prog
      (lambda (x)
	(match x
	       [(letrec ([,label* (lambda () ,tail*)] ...) ,tail)
		(let ((tail-exp (Tail label* tail)) (rest-of-exp (build-exp label* tail*)))
		  (append '(code) tail-exp rest-of-exp))])))
    (define Tail
      (lambda (label* x)
	(match x
	       [(if ,pred (,conseq) (,alt)) 
		(if (null? label*) `((if ,pred (jump ,conseq)) (jump ,alt))
		    (let ((next-label (car label*)))
		      (cond
		       [(eq? next-label conseq) `((if (not ,pred) (jump ,alt)))]
		       [(eq? next-label alt) `((if ,pred (jump ,conseq)))]
		       [else `((if ,pred (jump ,conseq)) (jump ,alt))])))]
	       [(begin ,effect* ...,tail) (append effect* (Tail label* tail))]		
	       [(,triv) `((jump ,triv))])))
    (Prog prog)))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

;;; Doesnot change from previous assignment

(define-who generate-x86-64
  (lambda (x)
    (define Program
      (lambda (x)
        (match x
	       [(code ,st* ...)
		(emit-program (for-each Stmt st*))])))
    (define Stmt
      (lambda (x)
        (match x
	       [(jump ,target) (emit-jump 'jmp target)]
	       [(if (,op ,x ,y) (jump ,lbl)) (begin (emit 'cmpq y x) (emit-jump (op->inst op) lbl))]
	       [(if (not (,op ,x ,y)) (jump ,lbl)) (begin (emit 'cmpq y x) (emit-jump (inst->inst^ (op->inst op)) lbl))]
	       [(set! ,v1 (,op ,v1 ,v2)) (emit (op->inst op) v2 v1)]
	       [(set! ,v1 ,v2) (guard (label? v2)) (emit 'leaq v2 v1)]
	       [(set! ,v1 ,v2) (emit 'movq v2 v1)]
	       [,label (emit-label label)])))
    (Program x)))


;;--------------------------------------------------------------------------------------------------------------------------------------------------------
;;--------------------------------------------------------------------------------------------------------------------------------------------------------

(define op->inst
  (lambda (op)
    (case op
      [(+) 'addq]
      [(-) 'subq]
      [(*) 'imulq]
      [(logand) 'andq]
      [(logor) 'orq]
      [(sra) 'sarq]
      [(=) 'je]
      [(<) 'jl]
      [(<=) 'jle]
      [(>) 'jg]
      [(>=) 'jge]
      [else (error who "unexpected binop ~s" op)])))


(define inst->inst^
  (lambda (inst)
    (case inst
      [(je) 'jne]
      [(jl) 'jge]
      [(jle) 'jg]
      [(jg) 'jle]
      [(jge) 'jl]
      )))


(define relop^
  (lambda (op)
    (case op
      ['> '<]
      ['< '>]
      ['<= '>=]
      ['= '=])))




(compiler-passes '(
		   verify-uil
		   remove-complex-opera*
		   flatten-set!
		   impose-calling-conventions				
		   uncover-frame-conflict
		   pre-assign-frame
		   assign-new-frame
		   (iterate
		    finalize-frame-locations
		    select-instructions
		    uncover-register-conflict
		    assign-registers
		    (break when everybody-home?)
		    assign-frame)
		   discard-call-live
		   finalize-locations
		   expose-frame-var
		   expose-basic-blocks
		   flatten-program
		   generate-x86-64
		   ))

