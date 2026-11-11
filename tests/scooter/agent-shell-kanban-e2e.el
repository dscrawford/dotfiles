;;; agent-shell-kanban-e2e.el --- Scooter's kanban boards and agent-shell tabs -*- lexical-binding: t -*-

;; The dotfiles open each card's chat in a tab (`scooter-kanban-open-in').

(defun e2e-kanban-card-id ()
  (scooter-kanban-card-id (cdr (scooter-kanban-at-point))))

(defun e2e-kanban-shell (id)
  (seq-find (lambda (b) (equal (map-nested-elt (buffer-local-value 'agent-shell--state b) '(:session :id)) id))
            (match-buffers '(derived-mode . agent-shell-mode))))

(defun e2e-kanban-tabs ()
  (mapcar (lambda (tab) (alist-get 'name tab)) (funcall tab-bar-tabs-function)))

(defun e2e-kanban-tab-of (buf)
  "The name of the one tab showing BUF, or an error."
  (let ((tabs (tab-bar-get-buffer-tab buf nil nil t)))
    (unless (= (length tabs) 1) (error "%s is in %d tabs: %S" buf (length tabs) (e2e-kanban-tabs)))
    (alist-get 'name (car tabs))))

(defun e2e-kanban ()
  (let ((old (e2e-old-buffer)))
    (unless (eq scooter-kanban-open-in 'tab) (error "Cards don't open in tabs: %S" scooter-kanban-open-in))
    (unless (eq (lookup-key (current-global-map) (kbd "C-c K")) #'scooter-kanban) (error "C-c K is not global"))
    (when (eq (lookup-key (current-global-map) (kbd "C-c C-k")) #'scooter-kanban) (error "C-c C-k is still scooter-kanban"))
    (with-current-buffer old
      (unless (eq (key-binding (kbd "C-c K")) #'scooter-kanban) (error "C-c K is not scooter-kanban in a shell"))
      (when (eq (key-binding (kbd "C-c C-k")) #'scooter-kanban) (error "C-c C-k is still scooter-kanban in a shell")))
    (switch-to-buffer old)
    (delete-other-windows)
    ;; C-c K from a shell: the board in a tab of its own, on the shell's card.
    (call-interactively #'scooter-kanban)
    (let ((board (get-buffer "*scooter-kanban*")))
      (unless (eq (window-buffer) board) (error "C-c K didn't select the board"))
      (set-buffer board)
      (unless (equal (e2e-kanban-tab-of board) "Kanban") (error "The board isn't in a Kanban tab: %S" (e2e-kanban-tabs)))
      (unless (tab-bar-get-buffer-tab old nil t) (error "The board replaced the shell's tab"))
      (unless (equal (e2e-kanban-card-id) "old") (error "Point is not on the shell's card"))
      (dolist (s '("Work  2 cards" "Design (1)" "Fix the login redirect" "KANBAN-NOTE · Agent · just now" "Review (1)" "Pinned"))
        (unless (e2e-has board s) (error "Board lacks %S:\n%s" s (e2e-text board))))
      (scooter-kanban-move-right)
      (unless (equal (e2e-kanban-card-id) "old") (error "Point left the moved card"))
      (unless (string-match-p "Review (2)" (e2e-text board)) (error "Card not in Review:\n%s" (e2e-text board)))
      ;; The move tells the card's agent, so the open shell sees the message.
      (e2e-wait (lambda () (e2e-has old "I moved this card from **Design** to **Review**")) "the move message")
      (e2e-idle old "the move's run to end")
      ;; RET on another card opens its chat in a tab of its own, named after it.
      (goto-char (point-min))
      (search-forward "Pinned")
      (scooter-kanban-visit)
      (e2e-wait (lambda () (e2e-kanban-shell "pinned")) "the pinned card's shell")
      (let ((pinned (e2e-kanban-shell "pinned")))
        ;; agent-shell shows the shell again once its session is picked:
        ;; still in its tab, not over the board.
        (e2e-wait (lambda () (map-nested-elt (buffer-local-value 'agent-shell--state pinned) '(:session :id)))
                  "the pinned shell's session")
        (accept-process-output nil 0.5)
        (unless (eq (window-buffer) pinned) (error "RET didn't select the card's shell"))
        (unless (equal (e2e-kanban-tab-of pinned) "Pinned") (error "The chat isn't in a Pinned tab: %S" (e2e-kanban-tabs)))
        (unless (equal (e2e-kanban-tab-of board) "Kanban") (error "Opening a card moved the board: %S" (e2e-kanban-tabs)))
        ;; C-c K in the chat goes back to the board's tab, opening none.
        (let ((n (length (e2e-kanban-tabs))))
          (with-current-buffer pinned (call-interactively #'scooter-kanban))
          (unless (eq (window-buffer) board) (error "C-c K didn't go back to the board"))
          (unless (= n (length (e2e-kanban-tabs))) (error "C-c K opened another tab: %S" (e2e-kanban-tabs))))
        ;; RET again switches to the chat's tab.
        (set-buffer board)
        (goto-char (point-min))
        (search-forward "Pinned")
        (scooter-kanban-visit)
        (unless (eq (window-buffer) pinned) (error "RET didn't switch to the chat's tab"))
        ;; Closing the tab closes the chat's shell.
        (tab-bar-close-tab)
        (when (buffer-live-p pinned) (error "Closing the tab left its shell open"))
        (when (member "Pinned" (e2e-kanban-tabs)) (error "The Pinned tab is still open: %S" (e2e-kanban-tabs)))))))
