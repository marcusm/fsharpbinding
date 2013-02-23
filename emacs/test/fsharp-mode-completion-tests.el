(require 'test-common)

;;; Jump to defn

(defconst finddeclstr1
  (let ((file (concat fs-file-dir "Program.fs")))
    (format "DATA: finddecl\nfile stored in metadata is '%s'\n%s:1:6\n<<EOF>>\n" file file))
  "A message for jumping to a definition in the same file")

(defconst finddeclstr2
  (let ((file (concat fs-file-dir "FileTwo.fs")))
    (format "DATA: finddecl\nfile stored in metadata is '%s'\n%s:12:11\n<<EOF>>\n" file file))
    "A message for jumping to a definition in the another file")

(check "jumping to local definition should not change buffer"
  (let ((f (concat fs-file-dir "Program.fs")))
    (in-ns fsharp-mode-completion
      (using-file f
        (_ filter-output nil finddeclstr1)
        (should (equal f (buffer-file-name)))))))

(check "jumping to local definition should move point to definition"
  (using-file (concat fs-file-dir "Program.fs")
    (in-ns fsharp-mode-completion
      (_ filter-output nil finddeclstr1)
      (should (equal (point) 18)))))

(check "jumping to definition in another file should open that file"
  (let ((f1 (concat fs-file-dir "Program.fs"))
        (f2 (concat fs-file-dir "FileTwo.fs")))
    (in-ns fsharp-mode-completion
      (using-file f1
        (_ filter-output nil finddeclstr2)
        (should (equal (buffer-file-name) f2))))))

(check "jumping to definition in another file should move point to definition"
  (in-ns fsharp-mode-completion
    (using-file (concat fs-file-dir "Program.fs")
      (_ filter-output nil finddeclstr2)
      (should (equal (point) 127)))))

;;; Error parsing

(defconst err-brace-str
  (mapconcat
     'identity
     '("DATA: errors"
       "[9:0-9:2] WARNING Possible incorrect indentation: this token is offside of context started at position (2:16)."
       "Try indenting this token further or using standard formatting conventions."
       "[11:0-11:2] ERROR Unexpected symbol '[<' in expression"
       "Followed by more stuff on this line"
       "[12:0-12:3] WARNING Possible incorrect indentation: this token is offside of context started at position (2:16).
Try indenting this token further or using standard formatting conventions."
       "<<EOF>>"
       "")
     "\n")
  "A list of errors containing a square bracket to check the parsing")

(defmacro check-filter (desc &rest body)
  "Test properties of filtered output from the ac-process."
  (declare (indent 1))
  `(check ,desc
     (find-file (concat fs-file-dir "Program.fs"))
     (in-ns fsharp-mode-completion
       (_ filter-output nil err-brace-str))
     ,@body))

(check-filter "error clears partial data"
  (should (equal "" ac-fsharp-partial-data)))

(check-filter "errors cause overlays to be drawn"
  (should (equal 3 (length (overlays-in (point-min) (point-max))))))

(check-filter "error overlay has expected text"
  (let* ((ov (overlays-in (point-min) (point-max)))
         (text (overlay-get (car-safe ov) 'help-echo)))
    (should (equal text
                   (concat "Possible incorrect indentation: "
                           "this token is offside of context started at "
                           "position (2:16)."
                           "\nTry indenting this token further or using standard "
                           "formatting conventions.")))))

(check-filter "first overlay should have the warning face"
  (let* ((ov (overlays-in (point-min) (point-max)))
         (face (overlay-get (car ov) 'face)))
    (should (eq 'fsharp-warning-face face))))

;; (check-filter "second overlay should have the error face"
;;   (let* ((ov (overlays-in (point-min) (point-max)))
;;          (face (overlay-get (cadr ov) 'face)))
;;     (should (eq 'fsharp-error-face face))))

;;; Project loading

(defmacro check-project-loading (desc &rest body)
  "Test fixture for loading projects, stubbing process-related functions.
Bound vars:
* load-cmd
  The string passed to log-psendstr"
  (declare (indent 1))
  `(check ,(concat "check project loading " desc)
     (let    (load-cmd)
       (flet ((fsharp-mode-completion/start-process ())
              (log-psendstr (proc cmd) (setq load-cmd cmd)))
         (in-ns fsharp-mode-completion
           ,@body)))))

(check-project-loading "raises error if not fsproj"
  (should-error (_ load-project "foo")))

(check-project-loading "updates the current project"
  (_ load-project "foo.fsproj")
  (should= "foo.fsproj" (@ current-project)))

(check-project-loading "loads the specified project using the ac process"
  (_ load-project "foo.fsproj")
  (should-match "foo.fsproj" load-cmd))

;;; Process handling

(defmacro check-handler (desc &rest body)
  "Test fixture for process handler tests.
Stubs out functions that call on the ac process."
  (declare (indent 1))
  `(check ,(concat "process handler " desc)
     (in-ns fsharp-mode-completion
       (flet ((log-to-proc-buf (p s))
              (log-psendstr    (p s))
              (ac-fsharp-can-make-request () t))
         ,@body))))

(check-handler "prints message on error"
  (flet ((message (s) (should-match "foo" err)))
    (_ filter-output nil "ERROR: foo")))

(check-handler "does not print message on type information error"
  (flet ((message (s) (should-not 'called)))
    (_ filter-output nil "ERROR: Could not get type information")))

;;; Tooltips and typesigs

(check-handler "shows popup if tooltip is requested"
  (flet ((popup-tip (s &rest _) (should-match "foo" s)))
    (fsharp-mode-completion/show-tooltip-at-point)
    (_ filter-output nil "DATA: tooltip\nfoo")))

(check-handler "does not show popup if typesig is requested"
  (let (tip)
    (flet ((popup-tip (s &rest _) (setq tip s)))
      (fsharp-mode-completion/show-typesig-at-point)
      (_ filter-output nil "DATA: tooltip\nfoo")
      (should-not tip))))

(check-handler "displays typesig in minibuffer if typesig is requested"
  (flet ((message (s) (should= "foo" s)))
    (fsharp-mode-completion/show-typesig-at-point)
    (_ filter-output nil "DATA: tooltip\nfoo")))