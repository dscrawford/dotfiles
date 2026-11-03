# shared/emacs/scooter-cards.nix
# Scooter approval cards that need input: the bridge offers scooter:answer and
# scooter:browser options; this collects the answers or opens the web UI.
{ }:

''
  (defun my/scooter-cards--read-answer (question)
    "Read the answer to QUESTION, an ask-user question alist, as a vector of strings."
    (let* ((options (append (map-elt question 'options) nil))
           (labels (mapcar (lambda (o) (map-elt o 'label)) options))
           (header (map-elt question 'header))
           (prompt (format "%s%s "
                           (if (and header (not (string-empty-p header))) (format "[%s] " header) "")
                           (map-elt question 'question)))
           (completion-extra-properties
            (list :annotation-function
                  (lambda (label)
                    (when-let* ((o (seq-find (lambda (o) (equal (map-elt o 'label) label)) options))
                                (d (map-elt o 'description)))
                      (concat "  " d))))))
      (vconcat
       (cond ((null labels) (list (read-string prompt)))
             ((eq (map-elt question 'multiSelect) t)
              (completing-read-multiple (concat prompt "(comma-separated, or type your own) ") labels))
             (t (list (completing-read prompt labels)))))))

  (defun my/scooter-cards--answered (respond args _result)
    (apply respond args))

  (defun my/scooter-cards--respond (respond &rest args)
    "Around `agent-shell--send-permission-response': handle Scooter's card options."
    (let* ((state (plist-get args :state))
           (option (plist-get args :option-id))
           (tool-call-id (plist-get args :tool-call-id)))
      (cond
       ((not (eq (map-nested-elt state '(:agent-config :identifier)) 'scooter))
        (apply respond args))
       ((equal option "scooter:browser")
        (with-current-buffer (map-elt state :buffer)
          (my/scooter-open-in-browser)))
       ((equal option "scooter:answer")
        (let ((answers (vconcat (mapcar #'my/scooter-cards--read-answer
                                        (map-nested-elt state (list :tool-calls tool-call-id :raw-input 'questions))))))
          (with-current-buffer (map-elt state :buffer)
            (my/scooter-request "_scooter/answer"
                                :params `((toolCallId . ,tool-call-id) (answers . ,answers))
                                :on-success (apply-partially #'my/scooter-cards--answered respond args)))))
       (t (apply respond args)))))

  (with-eval-after-load 'agent-shell
    (my/guard "scooter-cards"
      (advice-add 'agent-shell--send-permission-response :around #'my/scooter-cards--respond)))
''
