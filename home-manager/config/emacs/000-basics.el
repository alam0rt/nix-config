(add-hook `prog-mode-hook `display-line-numbers-mode)
(add-hook `after-init-hook `fancy-startup-screen)
;; allow Ctrl-C in terminal
(add-hook 'ansi-term-mode-hook
	  (lambda () (local-set-key (kdb "M-x" 'execute-extended-command)))
	  (lambda () (local-set-key (kbd "C-c" 'term-quit-subjob))))

(scroll-bar-mode -1)

(add-to-list 'default-frame-alist '(font . "Inconsolata"))

;; prefer y/n
(defalias `yes-or-no-p `y-or-n-p)

;; hotkeys
(global-set-key (kbd "<s-return>") `ansi-term)

(when window-system (global-prettify-symbols-mode t)) ;; prettify
(setq make-backup-files nil)
(setq auto-save-default nil)
(savehist-mode 1)
(setq savehist-file "~/.emacs_history")

;; Tramp
(require 'tramp-sh)
(setq tramp-remote-path
    (append tramp-remote-path
 	    '(tramp-own-remote-path)))
(require 'tramp)
(add-to-list 'tramp-remote-path "/run/current-system/profile/bin")
(add-to-list 'tramp-remote-path "/run/current-system/profile/sbin")
(add-to-list 'tramp-remote-path 'tramp-own-remote-path)
