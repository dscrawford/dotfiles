;;; scroll-nav-test.el --- scrolling and defun-navigation tests -*- lexical-binding: t; -*-

;; Run via tests/emacs/scroll-nav-run.sh, which extracts the elisp from
;; shared/emacs/{scrolling,navigation,guard}.nix into $SCROLLING_EL etc.

(require 'ert)
(require 'cl-lib)
(require 'pixel-scroll)

(defmacro my/guard (_label &rest body)
  (declare (indent 1))
  `(ignore-errors ,@body))

(defun my/test--load (env)
  (load (or (getenv env)
            (error "%s not set; run via tests/emacs/scroll-nav-run.sh" env))
        nil t t))

(defmacro my/test--with-fresh-global-map (&rest body)
  "Run BODY with a throwaway global keymap, so bindings do not leak."
  (declare (indent 0))
  `(let ((orig (current-global-map)))
     (unwind-protect
         (progn (use-global-map (make-sparse-keymap)) ,@body)
       (use-global-map orig))))

(defmacro my/test--with-scroll-defaults (&rest body)
  "Run BODY with the scrolling settings rebound, so loading cannot leak them."
  (declare (indent 0))
  `(let (pixel-scroll-precision-interpolate-page
         (scroll-conservatively 0)
         fast-but-imprecise-scrolling)
     ,@body))

(defmacro my/test--without-package (feature &rest body)
  "Run BODY with `require' of FEATURE failing, as on a host missing it."
  (declare (indent 1))
  `(let ((orig (symbol-function 'require)))
     (cl-letf (((symbol-function 'require)
                (lambda (feat &rest args)
                  (if (eq feat ,feature)
                      (signal 'file-missing (list "Cannot open load file" feat))
                    (apply orig feat args)))))
       ,@body)))

(defmacro my/test--with-package (feature required &rest body)
  "Run BODY with `require' of FEATURE stubbed, pushing it onto REQUIRED.
Any other feature loads for real, so a typo in the module fails the test."
  (declare (indent 2))
  `(let ((orig (symbol-function 'require)))
     (cl-letf (((symbol-function 'require)
                (lambda (feat &rest args)
                  (if (eq feat ,feature)
                      (push feat ,required)
                    (apply orig feat args)))))
       ,@body)))

;;; scrolling.nix

(ert-deftest my/scroll-settings-survive-missing-ultra-scroll ()
  "The keyboard knobs sit outside the guard, so a failed require keeps them."
  (my/test--with-scroll-defaults
    (my/test--without-package 'ultra-scroll
      (my/test--load "SCROLLING_EL")
      (should (eq pixel-scroll-precision-interpolate-page t))
      (should (= scroll-conservatively 3))
      (should (eq fast-but-imprecise-scrolling t)))))

(ert-deftest my/scroll-page-keys-are-interpolated ()
  "PgDn/PgUp animate rather than falling through to cua-scroll-up/down."
  (my/test--with-scroll-defaults
    (my/test--load "SCROLLING_EL")
    (let ((calls nil))
      (cl-letf (((symbol-function 'pixel-scroll-precision-interpolate)
                 (lambda (delta &rest _) (push delta calls)))
                ((symbol-function 'cua-scroll-up)
                 (lambda (&rest _) (push 'cua-up calls)))
                ((symbol-function 'cua-scroll-down)
                 (lambda (&rest _) (push 'cua-down calls))))
        (pixel-scroll-interpolate-down)
        (pixel-scroll-interpolate-up)
        (should (= (length calls) 2))
        (should (cl-every #'numberp calls))
        ;; Down scrolls by a negative pixel delta, up by a positive one.
        (should (< (nth 1 calls) 0))
        (should (> (nth 0 calls) 0))))))

(ert-deftest my/scroll-precision-mode-owns-the-page-keys ()
  "Upstream precondition, not coverage: the settings above only reach
PgUp/PgDn because pixel-scroll.el routes them through these two commands."
  (should (eq (lookup-key pixel-scroll-precision-mode-map (kbd "<next>"))
              'pixel-scroll-interpolate-down))
  (should (eq (lookup-key pixel-scroll-precision-mode-map (kbd "<prior>"))
              'pixel-scroll-interpolate-up)))

(ert-deftest my/scroll-owns-the-scroll-settings ()
  "No other module may set these; whichever loads last would win."
  (dolist (file (directory-files "shared/emacs" t "\\.nix\\'"))
    (unless (equal (file-name-nondirectory file) "scrolling.nix")
      (with-temp-buffer
        (insert-file-contents file)
        (should-not
         (re-search-forward (concat "pixel-scroll-precision-interpolate-page"
                                    "\\|scroll-conservatively"
                                    "\\|fast-but-imprecise-scrolling")
                            nil t))))))

(defun my/test--wheel (device delta)
  "Run the wheel advice for a DEVICE-class event carrying pixel DELTA.
Returns a plist of what reached the interpolator and the fallthrough."
  (let (interpolated fell-through)
    (cl-letf (((symbol-function 'device-class) (lambda (&rest _) device))
              ((symbol-function 'mwheel-event-window) (lambda (_) (selected-window)))
              ((symbol-function 'pixel-scroll-precision-interpolate)
               (lambda (d &rest _)
                 (setq interpolated
                       (list :delta d :time pixel-scroll-precision-interpolation-total-time)))))
      (my/ultra-scroll-interpolate-mouse
       (lambda (&rest _) (setq fell-through t))
       (list 'wheel-up nil 1 nil delta)))
    (list :interpolated interpolated :fell-through fell-through)))

(ert-deftest my/scroll-module-advises-ultra-scroll ()
  "The module installs the advice itself, or a dropped advice-add still passes."
  (my/test--with-scroll-defaults
    (my/test--load "SCROLLING_EL")
    (should (advice-member-p #'my/ultra-scroll-interpolate-mouse 'ultra-scroll))))

(ert-deftest my/scroll-wheel-mouse-clicks-animate-quickly ()
  "A wheel reports a constant 150px per click; animate it on the wheel's clock."
  (my/test--with-scroll-defaults
    (my/test--load "SCROLLING_EL")
    (let ((pixel-scroll-precision-interpolation-total-time 0.1)
          (result (my/test--wheel 'mouse '(0.0 . 150.0))))
      (should-not (plist-get result :fell-through))
      (should (equal (plist-get result :interpolated)
                     (list :delta 150 :time my/wheel-scroll-time)))
      (should (< my/wheel-scroll-time 0.1))
      ;; Let-bound, so PgUp/PgDn keep their slower page-sized animation.
      (should (= pixel-scroll-precision-interpolation-total-time 0.1)))))

(ert-deftest my/scroll-wheel-trackpad-keeps-ultra-scroll ()
  "Trackpads send real, varying deltas; ultra-scroll's direct path is better."
  (my/test--with-scroll-defaults
    (my/test--load "SCROLLING_EL")
    (let ((result (my/test--wheel 'touchpad '(0.0 . 37.0))))
      (should (plist-get result :fell-through))
      (should-not (plist-get result :interpolated)))))

(ert-deftest my/scroll-wheel-without-pixel-delta-falls-through ()
  "No pixel delta at all: nothing to animate, leave it to ultra-scroll."
  (my/test--with-scroll-defaults
    (my/test--load "SCROLLING_EL")
    (let ((result (my/test--wheel 'mouse nil)))
      (should (plist-get result :fell-through))
      (should-not (plist-get result :interpolated)))))

;;; navigation.nix

(ert-deftest my/nav-binds-defun-motion-without-scroll-on-jump ()
  "Without the package the keys still move by defun, never by paragraph."
  (my/test--with-fresh-global-map
    (my/test--without-package 'scroll-on-jump
      (my/test--load "NAVIGATION_EL"))
    (should (eq (key-binding (kbd "M-<up>")) 'beginning-of-defun))
    (should (eq (key-binding (kbd "M-<down>")) 'end-of-defun))))

(ert-deftest my/nav-wraps-defun-motion-in-scroll-on-jump ()
  "With the package loaded the keys run the jump through scroll-on-jump."
  (my/test--with-fresh-global-map
    (let ((wrapped nil) (required nil))
      (my/test--with-package 'scroll-on-jump required
        (cl-letf (((symbol-function 'scroll-on-jump-interactive)
                   (lambda (fn)
                     (push fn wrapped)
                     (lambda () (interactive) (list 'jumped fn)))))
          (my/test--load "NAVIGATION_EL")))
      (should (equal required '(scroll-on-jump)))
      (should (equal (nreverse wrapped) '(beginning-of-defun end-of-defun)))
      (dolist (key '("M-<up>" "M-<down>"))
        (let ((cmd (key-binding (kbd key))))
          (should (commandp cmd))
          (should-not (symbolp cmd))))
      (should (equal (call-interactively (key-binding (kbd "M-<up>")))
                     '(jumped beginning-of-defun))))))

(ert-deftest my/nav-wrapping-failure-leaves-both-keys-plain ()
  "A wrapper that throws must not leave one key animated and the other not."
  (my/test--with-fresh-global-map
    (let ((required nil))
      (my/test--with-package 'scroll-on-jump required
        (cl-letf (((symbol-function 'scroll-on-jump-interactive)
                   (let ((calls 0))
                     (lambda (fn)
                       (cl-incf calls)
                       (if (= calls 2)
                           (error "wrapper broke")
                         (lambda () (interactive) (list 'jumped fn)))))))
          (my/test--load "NAVIGATION_EL"))))
    (should (eq (key-binding (kbd "M-<up>")) 'beginning-of-defun))
    (should (eq (key-binding (kbd "M-<down>")) 'end-of-defun))))

(ert-deftest my/nav-missing-scroll-on-jump-warns-through-the-real-guard ()
  "The production my/guard, not the ignore-errors stub used elsewhere here:
a missing package has to surface in *Warnings*, not vanish."
  (let ((stub (symbol-function 'my/guard))
        (debug-on-error nil)
        (warnings nil))
    (unwind-protect
        (my/test--with-fresh-global-map
          (my/test--load "GUARD_EL")
          (my/test--without-package 'scroll-on-jump
            (cl-letf (((symbol-function 'display-warning)
                       (lambda (type msg &optional level &rest _)
                         (push (list type msg level) warnings))))
              (my/test--load "NAVIGATION_EL")))
          (should (equal (length warnings) 1))
          (pcase-let ((`(,type ,msg ,level) (car warnings)))
            (should (equal type '(emacs-init scroll-on-jump)))
            (should (string-prefix-p "scroll-on-jump disabled:" msg))
            (should (eq level :error)))
          (should (eq (key-binding (kbd "M-<up>")) 'beginning-of-defun)))
      (fset 'my/guard stub))))

(ert-deftest my/nav-owns-the-defun-motion-keys ()
  "No other module may bind them globally; the last one loaded would win.
Mode-local bindings are fine — eat rebinds them to reach the terminal."
  (dolist (file (directory-files "shared/emacs" t "\\.nix\\'"))
    (unless (equal (file-name-nondirectory file) "navigation.nix")
      (with-temp-buffer
        (insert-file-contents file)
        (should-not
         (re-search-forward "global-set-key[^\n]*M-<\\(up\\|down\\)>" nil t))))))

;;; upstream contract

(ert-deftest my/scroll-on-jump-interactive-contract ()
  "Pins the wrap's assumption against the real package: one function
argument in, a command out.  Skips when the package is not on load-path."
  (when-let* ((dir (getenv "SCROLL_ON_JUMP_DIR")))
    (add-to-list 'load-path dir))
  (skip-unless (locate-library "scroll-on-jump"))
  (require 'scroll-on-jump)
  (should (commandp (scroll-on-jump-interactive 'beginning-of-defun))))
