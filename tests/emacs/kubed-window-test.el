;;; kubed-window-test.el --- kubed window-reuse tests -*- lexical-binding: t; -*-

;; Run via tests/emacs/kubed-window-run.sh, which extracts the elisp from
;; shared/emacs/kubernetes.nix into $KUBERNETES_EL.

(require 'ert)
(require 'cl-lib)

(defmacro my/guard (_label &rest body)
  (declare (indent 1))
  `(ignore-errors ,@body))

(defvar my/test--loaded nil)

(defun my/test--load-kubernetes ()
  "Load the module once; it only defines settings, bindings, and advice."
  (unless my/test--loaded
    (load (or (getenv "KUBERNETES_EL")
              (error "KUBERNETES_EL not set; run via tests/emacs/kubed-window-run.sh"))
          nil t t)
    (setq my/test--loaded t)))

(defmacro my/test--with-two-windows (other &rest body)
  "Run BODY in a fresh two-window layout, OTHER bound to the second window."
  (declare (indent 1))
  `(let ((,other (split-window)))
     (unwind-protect (progn ,@body)
       (delete-other-windows))))

(defun my/test--kubed-action ()
  (cdr (assoc "\\`\\*[Kk]ubed" display-buffer-alist)))

(ert-deftest my/kubed-rule-covers-the-buffer-names-kubed-uses ()
  "Every buffer kubed displays is named from these two shapes."
  (my/test--load-kubernetes)
  (dolist (name '("*Kubed Pods@kubernetes-admin[default]*"
                  "*Kubed pod nginx in default*"
                  "*kubed-logs nginx/app in default[ctx]*"
                  "*kubed-config*"
                  "*kubed-diff*"
                  "*kubed-deployment-status*"
                  "*kubed-exec*"))
    (should (string-match-p "\\`\\*[Kk]ubed" name))))

(ert-deftest my/kubed-display-reuses-the-selected-window ()
  "The common case: no new window, and the current one shows the buffer."
  (my/test--load-kubernetes)
  (my/test--with-two-windows _other
    (let ((before (length (window-list))))
      (display-buffer (get-buffer-create "*Kubed pod nginx*"))
      (should (= (length (window-list)) before))
      (should (equal (buffer-name (window-buffer (selected-window)))
                     "*Kubed pod nginx*")))))

(ert-deftest my/kubed-display-from-dedicated-window-does-not-split ()
  "display-buffer-same-window refuses a dedicated window — the agent sidebar
is one — so without the use-some-window fallback this splits a third window."
  (my/test--load-kubernetes)
  (my/test--with-two-windows other
    (set-window-dedicated-p (selected-window) t)
    (unwind-protect
        (let ((before (length (window-list))))
          (display-buffer (get-buffer-create "*Kubed pod redis*"))
          (should (= (length (window-list)) before))
          (should (equal (buffer-name (window-buffer other)) "*Kubed pod redis*")))
      (set-window-dedicated-p (selected-window) nil))))

(ert-deftest my/kubed-rule-keeps-a-non-splitting-fallback ()
  "Both actions, in order: dropping the second reintroduces the split above."
  (my/test--load-kubernetes)
  (should (equal (my/test--kubed-action)
                 '((display-buffer-same-window display-buffer-use-some-window)))))

(ert-deftest my/kubed-explain-forces-its-help-buffer-same-window ()
  "kubed-explain renders into *Help*, which the regexp cannot match.
The module must install the advice itself; the test may not add it, or a
dropped advice-add still passes."
  (my/test--load-kubernetes)
  (should (advice-member-p #'my/kubed-explain-same-window 'kubed-explain))
  (let (seen)
    (my/kubed-explain-same-window
     (lambda (&rest _) (setq seen display-buffer-overriding-action)) "pod")
    (should (equal seen '((display-buffer-same-window))))))

(ert-deftest my/kubed-rule-leaves-other-buffers-alone ()
  "Nothing here may capture *Help* or other popups generally."
  (my/test--load-kubernetes)
  (dolist (name '("*Help*" "*Messages*" "*scratch*" "*kube-config*"))
    (should-not (string-match-p "\\`\\*[Kk]ubed" name))))
