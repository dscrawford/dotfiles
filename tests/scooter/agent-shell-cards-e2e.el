;;; agent-shell-cards-e2e.el --- Scooter approval cards in agent-shell -*- lexical-binding: t -*-

(defun e2e-cards-pending (buf)
  "The tool call id of BUF's open permission prompt, or nil."
  (car (seq-find (lambda (call) (map-elt (cdr call) :permission-request-id))
                 (map-elt (buffer-local-value 'agent-shell--state buf) :tool-calls))))

(defun e2e-cards-form (buf)
  "The id of BUF's pending question form, or nil."
  (car (seq-find (lambda (e) (eq (map-elt (cdr e) :status) 'pending))
                 (map-elt (buffer-local-value 'agent-shell--state buf) :elicitations))))

(defun e2e-cards-answer-questions (buf)
  (agent-shell-insert :text "ask me" :submit t :no-focus t :shell-buffer buf)
  (e2e-wait (lambda () (e2e-cards-form buf)) "the question form")
  (dolist (s '("DB" "Which database?" "Postgres" "Relational" "Which extras?"))
    (unless (e2e-has buf s) (error "Question form lacks %S:\n%s" s (e2e-text buf))))
  (let ((state (buffer-local-value 'agent-shell--state buf))
        (id (e2e-cards-form buf)))
    (agent-shell-elicitation--set-values
     state id '(("question_0" . "Postgres")
                ("question_1" . ("Cache" "Queue"))
                ("question_2_custom" . "billing")))
    (with-current-buffer buf
      (agent-shell-elicitation--respond :state state :id id :action 'accept)))
  (e2e-wait (lambda () (e2e-has buf "ANSWERED")) "the answered run")
  ;; Keyed by question, as AskUserQuestion reads them; the order is the bridge's.
  (dolist (want '("\"Which database?\":\"Postgres\"" "\"Which extras?\":\"Cache, Queue\"" "\"Name the service\":\"billing\""))
    (unless (e2e-has buf want) (error "Answer %s not sent:\n%s" want (e2e-text buf))))
  (e2e-idle buf "the answered turn to end"))

(defun e2e-cards-web-dismisses (buf)
  (agent-shell-insert :text "grant" :submit t :no-focus t :shell-buffer buf)
  (e2e-wait (lambda () (e2e-cards-pending buf)) "the grant card")
  (dolist (s '("AWS access to 123456789012 (high risk)" "s3:PutObject (write)"))
    (unless (e2e-has buf s) (error "Grant card lacks %S:\n%s" s (e2e-text buf))))
  (with-temp-file (getenv "TRIGGER_FILE") (insert "approve-in-web"))
  (e2e-wait (lambda () (e2e-has buf "WEB-APPROVED")) "the web approval")
  (e2e-wait (lambda () (e2e-has buf "Answered elsewhere")) "the card to say it was answered")
  (e2e-idle buf "the approved turn to end"))

(defun e2e-cards ()
  (let ((buf (e2e-start :session-strategy 'new)))
    (e2e-wait (lambda () (map-nested-elt (buffer-local-value 'agent-shell--state buf) '(:session :id))) "session/new")
    (e2e-cards-answer-questions buf)
    (e2e-cards-web-dismisses buf)))
