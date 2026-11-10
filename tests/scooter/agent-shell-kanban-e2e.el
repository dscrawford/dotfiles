;;; agent-shell-kanban-e2e.el --- Scooter's kanban boards beside agent-shell -*- lexical-binding: t -*-

(defun e2e-kanban-card-id ()
  (scooter-kanban-card-id (cdr (scooter-kanban-at-point))))

(defun e2e-kanban-shell (id)
  (seq-find (lambda (b) (equal (map-nested-elt (buffer-local-value 'agent-shell--state b) '(:session :id)) id))
            (match-buffers '(derived-mode . agent-shell-mode))))

(defun e2e-kanban ()
  (let ((old (e2e-old-buffer)))
    (unless (eq (lookup-key (current-global-map) (kbd "C-c C-k")) #'scooter-kanban) (error "C-c C-k is not global"))
    (with-current-buffer old
      (unless (eq (key-binding (kbd "C-c C-k")) #'scooter-kanban) (error "C-c C-k is not scooter-kanban in a shell")))
    (switch-to-buffer old)
    (delete-other-windows)
    (call-interactively #'scooter-kanban)
    (let ((board (get-buffer "*scooter-kanban*")))
      (unless (eq (window-buffer) board) (error "C-c C-k didn't select the board"))
      (set-buffer board)
      (unless (get-buffer-window old) (error "The board replaced the shell's window"))
      (unless (equal (e2e-kanban-card-id) "old") (error "Point is not on the shell's card"))
      (dolist (s '("Work  2 cards" "Design (1)" "Fix the login redirect" "KANBAN-NOTE · Agent · just now" "Review (1)" "Pinned"))
        (unless (e2e-has board s) (error "Board lacks %S:\n%s" s (e2e-text board))))
      (scooter-kanban-move-right)
      (unless (equal (e2e-kanban-card-id) "old") (error "Point left the moved card"))
      (unless (string-match-p "Review (2)" (e2e-text board)) (error "Card not in Review:\n%s" (e2e-text board)))
      ;; The move tells the card's agent, so the open shell sees the message.
      (e2e-wait (lambda () (e2e-has old "I moved this card from **Design** to **Review**")) "the move message")
      (e2e-idle old "the move's run to end")
      ;; RET on another card opens its chat in another window, the board kept.
      (goto-char (point-min))
      (search-forward "Pinned")
      (delete-other-windows)
      (scooter-kanban-visit)
      (e2e-wait (lambda () (e2e-kanban-shell "pinned")) "the pinned card's shell")
      (unless (eq (window-buffer) (e2e-kanban-shell "pinned")) (error "RET didn't select the card's shell"))
      (unless (get-buffer-window board) (error "Opening a card hid the board")))))
