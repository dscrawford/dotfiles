;;; agent-shell-files-e2e.el --- Scooter sandbox files over TRAMP -*- lexical-binding: t -*-

(setq my/scooter-sandbox-user (user-login-name)
      my/scooter-sandbox-directory (file-name-as-directory (getenv "SANDBOX_DIR")))

(defun e2e-files-buffer ()
  (let ((buf (e2e-start :session-id "old")))
    (e2e-wait (lambda () (e2e-has buf "HISTORY-ANSWER")) "history replay for sandbox files")
    buf))

(defun e2e-files-remote-p (file)
  (equal (file-remote-p file) "/scooter:old:"))

(defun e2e-files-dired (buf)
  (set-buffer
   (with-current-buffer buf
     (unless (eq (key-binding (kbd "C-c C-d")) #'my/scooter-dired) (error "C-c C-d is not my/scooter-dired"))
     (call-interactively #'my/scooter-dired)))
  (unless (derived-mode-p 'dired-mode) (error "my/scooter-dired left %S" (current-buffer)))
  (unless (equal default-directory (my/scooter-sandbox-file "old")) (error "dired is in %S" default-directory))
  (unless (save-excursion (goto-char (point-min)) (search-forward "hello.txt" nil t))
    (error "dired lacks hello.txt:\n%s" (buffer-string))))

(defun e2e-files-find-and-save (buf)
  (set-buffer
   (with-current-buffer buf
     (unless (eq (key-binding (kbd "C-c C-f")) #'my/scooter-find-file) (error "C-c C-f is not my/scooter-find-file"))
     (cl-letf (((symbol-function 'read-file-name)
		(lambda (_prompt dir &rest _) (expand-file-name "hello.txt" dir))))
       (call-interactively #'my/scooter-find-file))))
  (unless (e2e-files-remote-p buffer-file-name) (error "Visited %S, not the sandbox file" buffer-file-name))
  (unless (equal (buffer-string) "line one\nline two\n") (error "Sandbox file reads %S" (buffer-string)))
  (goto-char (point-max))
  (insert "saved from emacs\n")
  (save-buffer)
  (let ((on-disk (with-temp-buffer
                   (insert-file-contents (expand-file-name "hello.txt" my/scooter-sandbox-directory))
                   (buffer-string))))
    (unless (equal on-disk "line one\nline two\nsaved from emacs\n") (error "Saved %S" on-disk))))

(defun e2e-files-tool-output-link (buf)
  (with-temp-file (getenv "TRIGGER_FILE") (insert "files"))
  (e2e-wait (lambda () (e2e-has buf "FILES-ANSWER")) "the run citing a sandbox file")
  (e2e-wait (lambda () (with-current-buffer buf (not (shell-maker-busy)))) "the files run to end")
  (let ((cited (concat my/scooter-sandbox-directory "hello.txt:2")))
    (set-buffer
     (with-current-buffer buf
       (goto-char (point-min))
       (unless (search-forward (concat "wrote " cited) nil t) (error "No tool output citing %s:\n%s" cited (e2e-text buf)))
       (goto-char (- (point) 3))
       (unless (eq (key-binding (kbd "RET")) #'my/scooter-open-path-at-point)
         (error "RET on the cited path runs %S" (key-binding (kbd "RET"))))
       (window-buffer (my/scooter-open-path-at-point)))))
  (unless (e2e-files-remote-p buffer-file-name) (error "The link opened %S" buffer-file-name))
  (unless (equal (thing-at-point 'line t) "line two\n") (error "The link landed on %S" (thing-at-point 'line t))))

(defun e2e-sandbox-files ()
  (let ((buf (e2e-files-buffer)))
    (e2e-files-dired buf)
    (e2e-files-find-and-save buf)
    (e2e-files-tool-output-link buf)))
