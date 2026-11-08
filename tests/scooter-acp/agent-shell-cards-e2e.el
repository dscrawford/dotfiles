;;; agent-shell-cards-e2e.el --- Scooter approval cards in agent-shell -*- lexical-binding: t -*-

(defun e2e-cards-pending (buf)
  "The tool call id of BUF's open permission prompt, or nil."
  (car (seq-find (lambda (call) (map-elt (cdr call) :permission-request-id))
                 (map-elt (buffer-local-value 'agent-shell--state buf) :tool-calls))))

(defun e2e-cards-choose (buf option-id)
  (let* ((state (buffer-local-value 'agent-shell--state buf))
         (id (e2e-cards-pending buf)))
    (with-current-buffer buf
      (agent-shell--send-permission-response
       :client (map-elt state :client)
       :request-id (map-nested-elt state (list :tool-calls id :permission-request-id))
       :option-id option-id
       :state state
       :tool-call-id id))))

(defun e2e-cards-ask (buf text)
  (agent-shell-insert :text text :submit t :no-focus t :shell-buffer buf)
  (e2e-wait (lambda () (e2e-cards-pending buf)) (format "the %S card" text)))

(defun e2e-cards-answer-questions (buf)
  (e2e-cards-ask buf "ask me")
  (dolist (s '("[DB] Which database?" "Postgres — Relational" "(pick any)" "Open in browser"))
    (unless (e2e-has buf s) (error "Question card lacks %S:\n%s" s (e2e-text buf))))
  (let (opened)
    (cl-letf (((symbol-function 'browse-url) (lambda (url &rest _) (setq opened url))))
      (e2e-cards-choose buf "scooter:browser"))
    (unless (equal opened (format "%s/?thread=%s" my/scooter-url (map-nested-elt (buffer-local-value (quote agent-shell--state) buf) (quote (:session :id))))) (error "Open in browser went to %S" opened))
    (unless (e2e-cards-pending buf) (error "Open in browser dropped the prompt")))
  (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "Postgres"))
            ((symbol-function 'completing-read-multiple) (lambda (&rest _) '("Queue" "Cache")))
            ((symbol-function 'read-string) (lambda (&rest _) "billing")))
    (e2e-cards-choose buf "scooter:answer"))
  (e2e-wait (lambda () (e2e-has buf "ANSWERED")) "the answered run")
  (let ((want "ANSWERED {\"Which database?\":\"Postgres\",\"Which extras?\":\"Cache, Queue\",\"Name the service\":\"billing\"}"))
    (unless (e2e-has buf want) (error "Wrong answers sent:\n%s" (e2e-text buf))))
  (e2e-wait (lambda () (with-current-buffer buf (not (shell-maker-busy)))) "the answered turn to end"))

(defun e2e-cards-web-dismisses (buf)
  (e2e-cards-ask buf "grant")
  (dolist (s '("AWS account 123456789012, high risk" "s3:PutObject (write)"))
    (unless (e2e-has buf s) (error "Grant card lacks %S:\n%s" s (e2e-text buf))))
  (with-temp-file (getenv "TRIGGER_FILE") (insert "approve-in-web"))
  (e2e-wait (lambda () (e2e-has buf "WEB-APPROVED")) "the web approval")
  (e2e-wait (lambda () (not (e2e-has buf "Tool Permission"))) "the prompt to go away")
  (e2e-wait (lambda () (with-current-buffer buf (not (shell-maker-busy)))) "the approved turn to end"))

(defun e2e-cards ()
  (let ((buf (e2e-start :session-strategy 'new)))
    (e2e-wait (lambda () (map-nested-elt (buffer-local-value 'agent-shell--state buf) '(:session :id))) "session/new")
    (e2e-cards-answer-questions buf)
    (e2e-cards-web-dismisses buf)))

(defun e2e-forms-pending (buf)
  "The (id . form) of BUF's open question form, or nil."
  (seq-find (lambda (entry) (eq (map-elt (cdr entry) :status) 'pending))
            (map-elt (buffer-local-value 'agent-shell--state buf) :elicitations)))

(defun e2e-forms-ask (buf)
  (agent-shell-insert :text "ask me" :submit t :no-focus t :shell-buffer buf)
  (e2e-wait (lambda () (e2e-forms-pending buf)) "the question form")
  (when (e2e-cards-pending buf) (error "Questions still went to a permission card")))

(defun e2e-forms-submit (buf values)
  (let* ((state (buffer-local-value 'agent-shell--state buf))
         (form (e2e-forms-pending buf)))
    (agent-shell-elicitation--put state (car form)
                                  (agent-shell-elicitation--assoc-put (cdr form) :values values))
    (with-current-buffer buf
      (agent-shell-elicitation--respond :state state :id (car form) :action 'accept))))

(defun e2e-forms-answer-inline (buf)
  (e2e-forms-ask buf)
  (dolist (s '("DB" "Which database?" "Postgres" "Relational" "Extras" "Which extras?" "Queue" "Name the service" "Submit" "Decline"))
    (unless (e2e-has buf s) (error "Inline form lacks %S:\n%s" s (e2e-text buf))))
  (e2e-forms-submit buf '(("q0" . "Postgres") ("q1" . ("Queue" "Cache")) ("q2" . "billing")))
  (e2e-wait (lambda () (e2e-has buf "ANSWERED")) "the answered run")
  (let ((want "ANSWERED {\"Which database?\":\"Postgres\",\"Which extras?\":\"Cache, Queue\",\"Name the service\":\"billing\"}"))
    (unless (e2e-has buf want) (error "Wrong answers sent:\n%s" (e2e-text buf))))
  (e2e-wait (lambda () (with-current-buffer buf (not (shell-maker-busy)))) "the answered turn to end"))

(defun e2e-forms-web-answer-drops-form (buf)
  (e2e-forms-ask buf)
  (with-temp-file (getenv "TRIGGER_FILE") (insert "answer-in-web"))
  (e2e-wait (lambda () (e2e-has buf "WEB-ANSWERED")) "the web answer")
  (e2e-wait (lambda () (not (e2e-forms-pending buf))) "the form to settle")
  (e2e-wait (lambda () (with-current-buffer buf (not (shell-maker-busy)))) "the web-answered turn to end"))

(defun e2e-forms ()
  (setq agent-shell-elicitation--experimental-feature-enabled t)
  (unwind-protect
      (let ((buf (e2e-start :session-strategy 'new)))
        (e2e-wait (lambda () (map-nested-elt (buffer-local-value 'agent-shell--state buf) '(:session :id))) "session/new")
        (e2e-forms-answer-inline buf)
        (e2e-forms-web-answer-drops-form buf))
    (setq agent-shell-elicitation--experimental-feature-enabled nil)))

(defun e2e-ui-goto (buf action &optional key value)
  "Put point in BUF on the form control doing ACTION for field KEY and option VALUE."
  (with-current-buffer buf
    (goto-char (point-min))
    (let ((match (text-property-search-forward
                  'agent-shell-elicitation-control nil
                  (lambda (_ c) (and (eq (map-elt c :action) action)
                                     (or (null key) (equal (map-elt c :key) key))
                                     (equal (map-elt c :value) value))))))
      (unless match (error "No %S control for %S %S:\n%s" action key value (e2e-text buf)))
      (goto-char (prop-match-beginning match))
      (set-window-point (selected-window) (point)))))

(defun e2e-ui-keys (buf keys)
  "Type KEYS into BUF as a user would, through its keymaps and the minibuffer."
  (switch-to-buffer buf)
  (execute-kbd-macro (if (stringp keys) (kbd keys) keys)))

(defun e2e-ui-press (buf action &optional key value typed)
  (e2e-ui-goto buf action key value)
  (e2e-ui-keys buf (if typed (vconcat (kbd "RET") typed (kbd "RET")) "RET")))

(defun e2e-forms-key-in (buf answers want)
  "Answer BUF's open question form by keypress and expect the run to come back with WANT.
ANSWERS are `e2e-ui-press' arguments, after TAB RET has picked the first option."
  (switch-to-buffer buf)
  (agent-shell-elicitation-jump-to-latest-form)
  (call-interactively (key-binding (kbd "TAB")))
  (e2e-ui-keys buf "RET")
  (unless (equal (map-nested-elt (cdr (e2e-forms-pending buf)) '(:values "q0")) "Postgres")
    (error "TAB RET did not pick the first option:\n%s" (e2e-text buf)))
  (dolist (a answers) (apply #'e2e-ui-press buf a))
  (e2e-ui-press buf 'submit)
  (condition-case nil
      (e2e-wait (lambda () (e2e-has buf want)) "the answer")
    (error (error "Submit did not resume the run with %s:\n%s" want (e2e-text buf))))
  (e2e-wait (lambda () (with-current-buffer buf (not (shell-maker-busy)))) "the keyed-in turn to end"))

(defconst e2e-forms-picked
  '((toggle "q1" "Queue") (toggle "q1" "Cache") (read "q2" nil "billing")))

(defconst e2e-forms-picked-answer
  "ANSWERED {\"Which database?\":\"Postgres\",\"Which extras?\":\"Cache, Queue\",\"Name the service\":\"billing\"}")

(defun e2e-forms-by-keys ()
  (setq agent-shell-elicitation--experimental-feature-enabled t)
  (unwind-protect
      (let ((buf (e2e-start :session-strategy 'new)))
        (e2e-wait (lambda () (map-nested-elt (buffer-local-value 'agent-shell--state buf) '(:session :id))) "session/new")
        (e2e-forms-ask buf)
        (e2e-forms-key-in buf e2e-forms-picked e2e-forms-picked-answer)
        (e2e-forms-ask buf)
        (e2e-forms-key-in
         buf '((custom "q0_other" nil "MySQL") (toggle "q1" "Cache") (custom "q1_other" nil "Search") (read "q2" nil "ledger"))
         "ANSWERED {\"Which database?\":\"MySQL\",\"Which extras?\":\"Cache, Search\",\"Name the service\":\"ledger\"}")
        (let ((loaded (e2e-start :session-id "asking")))
          (e2e-wait (lambda () (e2e-forms-pending loaded)) "the question left open in the loaded conversation")
          (e2e-forms-key-in loaded e2e-forms-picked e2e-forms-picked-answer))
        (let ((old (e2e-start :session-id "old")))
          (e2e-wait (lambda () (e2e-has old "HISTORY-ANSWER")) "history replay")
          (sleep-for 0.5)
          (with-temp-file (getenv "TRIGGER_FILE") (insert "ask-in-web"))
          (e2e-wait (lambda () (e2e-forms-pending old)) "the question from a web-started run")
          (e2e-forms-key-in old e2e-forms-picked e2e-forms-picked-answer)))
    (setq agent-shell-elicitation--experimental-feature-enabled nil)))

(defun e2e-trigger (what)
  (with-temp-file (getenv "TRIGGER_FILE") (insert what))
  (e2e-wait (lambda () (not (file-exists-p (getenv "TRIGGER_FILE")))) (format "the %s trigger" what)))

(defun e2e-forms-answer-reaches-scooter ()
  "A form answered by keypress resumes the run even when Scooter is slow to start it or turns it down."
  (setq agent-shell-elicitation--experimental-feature-enabled t)
  (unwind-protect
      (let* ((process-environment (cons "SCOOTER_REQUEST_TIMEOUT_MS=1000" process-environment))
             (buf (e2e-start :session-strategy 'new)))
        (e2e-wait (lambda () (map-nested-elt (buffer-local-value 'agent-shell--state buf) '(:session :id))) "session/new")
        (e2e-trigger "slow-resume")
        (e2e-forms-ask buf)
        (e2e-forms-key-in buf e2e-forms-picked e2e-forms-picked-answer)
        (e2e-trigger "reject-resume")
        (e2e-forms-ask buf)
        (let ((first (car (e2e-forms-pending buf))))
          (switch-to-buffer buf)
          (agent-shell-elicitation-jump-to-latest-form)
          (dolist (a e2e-forms-picked) (apply #'e2e-ui-press buf a))
          (e2e-ui-press buf 'select "q0" "SQLite")
          (e2e-ui-press buf 'submit)
          (condition-case nil
              (e2e-wait (lambda () (and (e2e-has buf "interrupt toolu_ask is not waiting")
                                        (not (equal (car (e2e-forms-pending buf)) first))
                                        (e2e-forms-pending buf)))
                        "the refusal and the question asked again")
            (error (error "A refused answer was not reported and asked again:\n%s" (e2e-text buf)))))
        (e2e-forms-key-in buf e2e-forms-picked e2e-forms-picked-answer))
    (setq agent-shell-elicitation--experimental-feature-enabled nil)))
