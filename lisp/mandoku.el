;;; mandoku.el --- A tool to access repositories of premodern Chinese texts 
;; -*- coding: utf-8 -*-
;; created [2001-03-13T20:32:32+0800]  (as smart.el)
;; renamed and refactored [2010-01-08T17:01:43+0900]
;;
;; Copyright (c) 2001-2017 Christian Wittern
;;
;; Author: Christian Wittern <cwittern@gmail.com>
;; URL: http://www.mandoku.org
;; Version: 0.9
;; Keywords: convenience
;; Package-Requires: ((org "8") (github-clone "20150705.1705"))
;; This file is not part of GNU Emacs.

;;; Commentary:

;; "Emacs outshines all other editing software in approximately the
;; same way that the noonday sun does the stars. It is not just bigger
;; and brighter; it simply makes everything else vanish."
;; -Neal Stephenson, "In the Beginning was the Command Line"

;; This package brings the power of Emacs to people working with
;; premodern Chinese texts by extending org-mode and providing
;; routines for helping with reading, annotating and translating of
;; such texts.  For more information see http://www.mandoku.org

;;; License

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING. If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.
;;; Code:

(require 'org)
(require 'mandoku-remote)
(require 'mandoku-link)
(require 'magit)
(require 'mandoku-github)
(require 'git)
(require 'url)
(require 'url-handlers)
(require 'cl)
(require 'hi-lock)

(defgroup mandoku nil
  "Main customization group for Mandoku.  The most frequently used settings are provided here.")
(defgroup mandoku-system nil
  "Customization group for advanced techincal settings in Mandoku.")
(defgroup mandoku-user nil
  "Customization group for specialized user settings in Mandoku." )

(defcustom mandoku-base-dir nil
  "This is the root of the mandoku hierarchy, this needs to be provided by the user in its init file"
  :type '(directory)
  :group 'mandoku-user)
(defcustom mandoku-do-remote t
  "Set to t if we want to query a remote repository.  This is the default setting and should not usually be changed."
  :type '(boolean)
  :group 'mandoku)

(defcustom mandoku-preferred-edition nil "Preselect a certain edition to avoid repeated selection"
  :type '(string)
  :group 'mandoku-user)

(defcustom mandoku-index-all-editions nil "If not nil, then display all editions in the Mandoku Index display."
  :type '(string)
  :group 'mandoku-user)

(defcustom mandoku-annot-drawer ":zhu:" "Start of a mandoku annotation. The end will always be :end: on a line by itself. Restart mandoku after changing this. Existing annotations will not be updated."
  :type '(string)
  :group 'mandoku)

(defvar mandoku-annot-start (concat "\n\s*" mandoku-annot-drawer "\n"))
(defconst mandoku-annot-end ":end:\n")

  
;;;###autoload
(defconst mandoku-lisp-dir (file-name-directory (or load-file-name (buffer-file-name)))
  "directory of mandoku lisp code")
(defvar mandoku-subdirs (list "text" "images" "meta" "temp" "temp/imglist" "system" "work" "index" "user" "notes"))
;; it probably does not much sense to do this here, but anyway, this is the idea...
(defcustom mandoku-grep-command "bzgrep" "The command used for mandoku's internal search function. On Windows, needs to be 'grep'."
    :type '(string)
  :group 'mandoku-system)

(defvar mandoku-local-init-file nil)
;; we store the http password for gitlab in memory for one session
;; todo: make this a per server setting!
(defcustom mandoku-user-account nil
  "The name of the user account for mandoku. "
  :type '(string)
  :group 'mandoku-user)
  
(defcustom mandoku-gh-rep "kanripo"
  "The name of the repository on GitHub. This is GitHub account that holds the files of the texts, it defaults to 'kanripo' and should usually not be changed."
  :type '(string)
  :group 'mandoku-user)
  
(defcustom mandoku-gh-user nil
  "The name of the account on GitHub to be used."
  :type '(string)
  :group 'mandoku-user)
  
(defcustom mandoku-gh-server "github.com"
  "The server for the GitHub site."
  :type '(string)
  :group 'mandoku-user)

(defcustom mandoku-gh-imglist-template "https://raw.githubusercontent.com/%s/%s/_data/imglist/%s.%s"
  "The template used to construct the URl for retrieving the list of images for a specific edition.
This should only be changed in rare circumstances. Four strings will be provided for this template:
- github repository
- text-number
- text-number_juan-number
- file extension
"
  :type '(string)
  :group 'mandoku-system)
  
(defvar mandoku-user-password nil)
(defcustom mandoku-string-limit 10
  "Maximum length for a search string"
  :type '(integer)
  :group 'mandoku-system)

(defcustom mandoku-index-display-limit 2000
  "Number of initial search results to be displayed without tabulating the buffer"
  :type '(integer)
  :group 'mandoku)

;; Defined somewhere in this file, but used before definition.
;;;###autoload
(defcustom mandoku-repositories-alist '(("dummy" . "http://www.example.com"))
  "List of the reopositories to query. The values are the name of the repository as key and its URL as value."
  :type '(alist :key-type 'string :value-type 'string)
  :group 'mandoku-system)

(defvar mandoku-md-menu)
(defvar mandoku-position nil "Position as a list of textid edition page line" )
(defvar mandoku-position-marker (make-marker) "Marker for the last position in the text")
(defvar mandoku-search-for nil "Last search term for the mandoku search." )
(defvar mandoku-catalog nil)
(defvar mandoku-local-index-list nil)
(defvar mandoku-for-commit-list nil)
(defvar mandoku-extra-reps '("KR-Workspace" "KR-Gaiji" "KR-Catalog")
  "Additional data repositories from Kanseki Repository:
'KR-Workspace' : Workspace for the user.
'KR-Gaiji' : Mapping table and images for non-system characters.
'KR-Catalog' : Additional metadata for the texts.
")
(defvar mandoku-location-plist nil
  "Plist holds the most recent stored location with associated information.")
;; TODO: add drawers
;; '(org-drawers (quote ("PROPERTIES" "CLOCK" "LOGBOOK" "zhu")))

;; ** Textfilters
;; we have one default textfilter, which always exists and can be dynamically treated. 
(defvar mandoku-default-textfilter (make-hash-table :test 'equal) )
(setplist 'mandoku-default-textfilter '(:name "Default" :active t))
;; more textfilters can be added to the list
(defvar mandoku-textfilter-list (list 'mandoku-default-textfilter))
;; switch the whole filter mechanism on or off.
(defvar mandoku-use-textfilter nil)
;; control, which collections are used.
;; this could be a list? currently only one subcoll allowed, but it could be a regex understood by the shell ZB6[rq]
(defvar mandoku-datefilter 10000)
;; this is the number of characters to use in an ngram for the index; nil means "off"
(defcustom mandoku-ngram-n nil
  "This is the number of characters to use in an ngram for the index; nil means do not calculate ngrams."
  :type '(integer)
  :group 'mandoku)

(defvar mandoku-search-limit-to-coll nil)
;; ** Catalogs
;; (defvar mandoku-catalogs-alist nil)
;; (defvar mandoku-catalog-path-list nil)
;; (defvar mandoku-catalog-user-path-list nil)
;;;###autoload
(defvar mandoku-titles-by-date nil)
(defvar mandoku-titles-by-taisho nil "Lookup table for titles by Taisho volume or number.")
(defvar mandoku-titles-file nil "Title table, includes mappings to other collections.")
(defvar mandoku-git-use-http t)
(defvar mandoku-gaiji-images-path nil)

(defvar mandoku-initialized-p nil)


(defvar mandoku-file-type ".txt")
;;we skip: 》《 
(defvar mandoku-punct-regex-post "\\([^
]\\)\\([　-〇〉」』】〗〙〛〕-㄀︀-￯)]+\\)")
(defvar mandoku-punct-regex-pre "\\([^
]\\)\\([(〈「『【〖〘〚〔]+\\)")

(defvar mandoku-kanji-regex "\\([㐀-鿿𠀀-𪛟]+\\)")

(defvar mandoku-regex "<[^>]*>\\|[　-㏿＀-￯\n¶]+\\|\t[^\n]+\n\\|^[ \t]\\|\n\\|^#[^\n]+\n")
;; that is: two uppercase characters, followed by a number and one or more upper or lowercase characters followed by 4 digits.
(defvar mandoku-textid-regex  "[A-Z]\\{2\\}[0-9][A-z]+[0-9]\\{4\\}")

(defvar mandoku-w32-p
  (or (equal system-type 'windows-nt)
      (equal system-type 'ms-dos)))


;;[2014-06-03T14:31:46+0900] better handling of git
(defcustom mandoku-git-program
  (if mandoku-w32-p
      (concat "\"" (executable-find "git") "\"")
    (executable-find "git"))
  "Name of the git executable used by mandoku."
  :type '(string)
  :group 'mandoku-system)

(defcustom mandoku-rg-program
  (if mandoku-w32-p
      (concat "\"" (executable-find "rg") "\"")
    (executable-find "rg"))
  "Name of the rg executable used by mandoku."
  :type '(string)
  :group 'mandoku-system)

(defcustom mandoku-python-program 
  (if mandoku-w32-p
      (concat "\"" (executable-find "python") "\"")
      (executable-find "python"))
  "Name of the python executable used by mandoku."
  :type '(string)
  :group 'mandoku-system)

(defcustom mandoku-github-remote-name "kanripo"
  "Name of the remote used for the github site."
  :type '(string)
  :group 'mandoku-system)
  
;; Add this since it appears to miss in emacs-2x
(or (fboundp 'replace-in-string)
    (defun replace-in-string (target old new)
      (replace-regexp-in-string old new  target)))


(defun mandoku-setup-dirvars ()
  (defvar mandoku-text-dir (expand-file-name (concat mandoku-base-dir "text/")))
  (defvar mandoku-image-dir (expand-file-name (concat mandoku-base-dir "images/")))
  (defvar mandoku-index-dir (expand-file-name  (concat mandoku-base-dir "index/")))
  (defvar mandoku-meta-dir (expand-file-name  (concat mandoku-base-dir "meta/")))
  (defvar mandoku-temp-dir (expand-file-name  (concat mandoku-base-dir "temp/")))
  (defvar mandoku-sys-dir (expand-file-name  (concat mandoku-base-dir "system/")))
  (defvar mandoku-user-dir (expand-file-name  (concat mandoku-base-dir "user/")))
  (defvar mandoku-work-dir (expand-file-name  (concat mandoku-base-dir "work/")))
  (defvar mandoku-filters-dir (if (file-exists-p (concat mandoku-base-dir "KR-Workspace/Texts/"))
				  (expand-file-name (concat mandoku-base-dir "KR-Workspace/Texts/"))
			       (expand-file-name  (concat mandoku-work-dir "filters/"))))
;;housekeeping files
  (defvar mandoku-log-file (concat mandoku-sys-dir "mandoku.log"))
  (defvar mandoku-local-catalog (concat mandoku-meta-dir "local-texts.txt"))
  (defvar mandoku-download-queue (concat mandoku-sys-dir "mandoku-to-download.queue"))
  (defvar mandoku-index-queue (concat mandoku-sys-dir "mandoku-to-index.queue"))
  (defvar mandoku-indexed-texts (concat mandoku-sys-dir "indexed-texts.txt"))
  (defvar mandoku-config-cfg (concat mandoku-user-dir "mandoku-settings.cfg"))
)  


;;; ** working with catalog files, prepare the metadata
(defun mandoku-update-catalog-alist ()
  ;; these variables are reset from the metadata
  (setq mandoku-catalog-path-list nil)
  (setq mandoku-repositories-alist nil)
  ;; populated anew
  (setq mandoku-catalogs-alist nil)
  (add-to-list 'mandoku-catalog-path-list mandoku-meta-dir)
  (dolist (p package-activated-list)
    (if (string-match "mandoku-meta" (symbol-name p))
	;; get the values for url and catalog dir from the meta-packages:
	(let (( url (symbol-value (intern (concat (symbol-name p) "-url"))))
	      (path (symbol-value (intern (concat (symbol-name p) "-dir")))))
	  (add-to-list 'mandoku-repositories-alist url )
	  (add-to-list 'mandoku-catalog-path-list path))))
  (dolist (e mandoku-catalog-user-path-list)
    (add-to-list 'mandoku-catalog-path-list (expand-file-name (concat mandoku-meta-dir e))))
  (dolist (px mandoku-catalog-path-list )
    (dolist (file (directory-files px nil ".*txt$" ))
      (if (not (or (string-match file mandoku-catalog)
	       (string-match file mandoku-local-catalog)
	       ))
	  (add-to-list 'mandoku-catalogs-alist 
		       (cons (file-name-sans-extension file) (concat px "/" file))))))
)

(defun mandoku-update-subcoll-list ()
  ;; dont really need this outer loop at the moment...
  (message "Subcoll start ")
  (dolist (x mandoku-repositories-alist)
    (message "Processing repo %s " (car x))
    (let ((scfile (concat mandoku-sys-dir "subcolls.txt")))
      (with-current-buffer (find-file-noselect scfile t)
	(erase-buffer)
	(insert (format-time-string ";;[%Y-%m-%dT%T%z]\n" (current-time)))
	(dolist (y mandoku-catalogs-alist)
	  (message "Processing %s " (car y))
	  (let ((tlist 
		 (with-current-buffer (find-file-noselect (cdr y))
		   (org-map-entries 'mandoku-get-header-item "+LEVEL<=2"))))
	    (with-current-buffer (file-name-nondirectory scfile)
	      (dolist (z tlist)
		(insert (concat (car z) "\t" (car (last z)) "\n")))
	      )))
	      (save-buffer)
	      (kill-buffer (file-name-nondirectory scfile) )))))

	  
(defun mandoku-update-title-lists ()
  (dolist (x mandoku-catalogs-alist)
    ;; ("ZB6 佛部" . "/Users/chris/projects/meta/zb-cbeta.org")
    (message (concat  "Reading catalog file for: "  (car x)))
    (let* ((titlefile (concat mandoku-sys-dir (car (split-string (car x))) "-titles.txt"))
	   (volfile (concat mandoku-sys-dir (car (split-string (car x))) "-volumes.txt"))
	   (lookupfile (concat mandoku-sys-dir (car (split-string (car x))) "-lookup.txt"))
	  (catfile (cdr x))
	  (tlist 
	   (with-current-buffer (find-file-noselect catfile)
	     (org-map-entries 'mandoku-get-header-item "+LEVEL=3"))))
      (message (format "%s" (concat "Updating file: " titlefile)))
      (with-current-buffer (find-file-noselect titlefile t)
	(erase-buffer)
	(insert (format-time-string ";;[%Y-%m-%dT%T%z]\n" (current-time)))
	(dolist (y tlist)
	  (insert (concat (car y) "\t" (car (last y)) "\n")))
	(save-buffer)
	(kill-buffer))
      (message (concat "Updating file: " volfile))
      (with-current-buffer (find-file-noselect volfile t)
	(erase-buffer)
	(insert (format-time-string ";;[%Y-%m-%dT%T%z]\n" (current-time)))
	(dolist (y tlist)
	  ;; if there is a CBETA number, it is in the middle: we want the first part before "n"
	  (if (< 2 (length y))
	      (insert (concat (car y) "\t"  (car (split-string (car (cdr y)) "n"))  "\n"))))
	(save-buffer)
	(kill-buffer))
      (with-current-buffer (find-file-noselect lookupfile t)
	(erase-buffer)
	(insert (format-time-string ";;[%Y-%m-%dT%T%z]\n" (current-time)))
	(dolist (y tlist)
	  ;; if there is a CBETA number, it is in the middle: we want the first part before "n"
	  (if (< 2 (length y))
	      (insert (concat (car (cdr y)) "\t"  (car y)  "\n"))))
	(save-buffer)
	(kill-buffer))
      (message "Done!")
;;      (kill-buffer catfile)
  )))

(defun mandoku-get-header-item ()
  (let ((end (save-excursion(end-of-line) (point)))
	(begol (save-excursion (beginning-of-line) (search-forward " ") )))
    (split-string 
     (replace-regexp-in-string org-bracket-link-regexp "\\3" 
			       (buffer-substring-no-properties begol end)))))

(defun mandoku-read-lookup-list () 
  "read the titles table"
  (setq mandoku-lookup (make-hash-table :test 'equal))
  (dolist (x mandoku-catalogs-alist)
    (when (file-exists-p (concat mandoku-sys-dir (car (split-string (car x))) "-lookup.txt"))
      (with-temp-buffer
        (let ((coding-system-for-read 'utf-8)
              textid)
          (insert-file-contents (concat mandoku-sys-dir (car (split-string (car x))) "-lookup.txt"))
          (goto-char (point-min))
          (while (re-search-forward "^\\([A-z0-9]+\\)	\\([^	
]+\\)" nil t)
	     (puthash (match-string 1) (match-string 2) mandoku-lookup)))))))

(defun mandoku-read-indexed-texts()
  "read the list of indexed texts into the variable."
    (when (file-exists-p  mandoku-indexed-texts)
    (with-temp-buffer
      (let ((coding-system-for-read 'utf-8)
	    textid)
	(insert-file-contents mandoku-indexed-texts)
	(goto-char (point-min))
	(while (re-search-forward mandoku-textid-regex nil t)
	  (add-to-list 'mandoku-local-index-list (match-string 0))))
      ))
)
(defun mandoku-read-txt-titles ()
  "This is the table which also includes references to other collections."
;  (interactive)
  (setq mandoku-txtid-by-other (make-hash-table :test 'equal))
  (when (file-exists-p mandoku-titles-file)
    (with-temp-buffer
      (let ((coding-system-for-read 'utf-8)
	    textid line vol otherid)
	(insert-file-contents mandoku-titles-file)
	(goto-char (point-min))
	(while (not (eobp))
	  (when (looking-at "KR")
	    (setq line (split-string (thing-at-point 'line t)))
	    (setq textid (car line))
	    (dolist (l (cdr line))
	      (when (string-match "@\\(.*\\)" l)
		(puthash (match-string 1 l) textid mandoku-txtid-by-other))))
	  (forward-line 1)
	    ))
	  )))
	
(defun mandoku-read-titletables () 
  "read the titles table"
  (interactive)
  (setq mandoku-subcolls (make-hash-table :test 'equal))
;;   (when (file-exists-p (concat mandoku-sys-dir  "subcolls.txt"))
;;     (with-temp-buffer
;;       (let ((coding-system-for-read 'utf-8)
;; 	    textid)
;; 	(insert-file-contents (concat mandoku-sys-dir "subcolls.txt"))
;; 	(goto-char (point-min))
;; 	(while (re-search-forward "^\\([A-z0-9]+\\)	\\([^	
;; ]+\\)" nil t)
;; 	  (puthash (match-string 1) (match-string 2) mandoku-subcolls)))))

  (setq mandoku-titles (make-hash-table :test 'equal))
  (setq mandoku-textdates (make-hash-table :test 'equal))
  (when (file-exists-p mandoku-titles-by-date)
    (with-temp-buffer
      (let ((coding-system-for-read 'utf-8)
	    textid)
	(insert-file-contents mandoku-titles-by-date)
	(goto-char (point-min))
	(while (re-search-forward "^\\([A-z0-9]+\\)	\\([^	]+\\)	\\([^	
]+\\)" nil t)
	  (puthash (match-string 1) (match-string 3) mandoku-titles)
	  (puthash (match-string 1) (match-string 2) mandoku-textdates)
	  (if (< (length (match-string 1)) 6)
	      (puthash (match-string 1) (match-string 3) mandoku-subcolls))
	      
	  )))))

;; catalog / title handling

(defun char-to-ucs (char)
  char
)
(defun mandoku-char-to-ucs (char)
  (format "%04x" (char-to-ucs char))
)

(defun mandoku-what (char)
  (interactive (list (char-after)))
	(message (mandoku-char-to-ucs char))
)

(defun mandoku-copy-clean (beg end)
  (interactive "r")
  (kill-new
   (mandoku-remove-punct-and-markup
    (buffer-substring-no-properties beg end)))
)

(defun mandoku-grep (beg end)
  (interactive "r")
  (let ((index-buffer (get-buffer-create "*temp-mandoku*"))
     (result-buffer (get-buffer-create "*Mandoku Index*")))
    (mandoku-grep-internal (buffer-substring-no-properties beg end)
			   index-buffer result-buffer)))


;;;###autoload
(defun mandoku-show-catalog ()
  (interactive)
  (unless mandoku-initialized-p
    (mandoku-initialize))
  (find-file mandoku-catalog)
  (delete-other-windows)
  )

(defun mandoku-update-catalog ()
  (with-current-buffer (find-file-noselect mandoku-catalog)
    (erase-buffer)
    (insert "# -*- mode: mandoku-view; -*-
#+DATE: " (format-time-string "%Y-%m-%d\n" (current-time))  
"#+TITLE: 漢籍リポジトリ目録


[[file:local-texts.txt][Local (downloaded) texts 個人漢籍]]

[[mandoku:*:KR][Kanseki Repository 漢籍リポジトリ]]

")
  (mandoku-view-mode)
  (goto-char (point-min))
  (save-buffer)
))

;; (defun mandoku-catalog-no-update-needed-p () 
;;   "Check for updates that might be necessary for catalog"
;;   (let ((update-needed nil)
;; 	(mandoku-catalog (or mandoku-catalog
;; 			   (expand-file-name "mandoku-catalog.txt" (concat mandoku-base-dir "/meta")))))
;;     (mandoku-update-catalog-alist)
;;     (with-current-buffer (find-file-noselect mandoku-catalog)
;;       (dolist (y mandoku-catalogs-alist)
;; 	(unless update-needed
;; 	  (goto-char (point-min))
;; 	  (unless (search-forward (car y) nil t)
;; 	    (setq update-needed t)))))
;;     (not update-needed)))

		   
      
(defun mandoku-initialize ()
  (let* ((defmd (if (string-match "windows" (symbol-name system-type))
		    "c:\\krp"
		  "~/krp"))
	 (md 
	  (if (not mandoku-base-dir)
	      (if (file-exists-p (expand-file-name defmd))
		  (expand-file-name defmd)
		(read-string
		 (format "Please input the full path to the base directory for Mandoku (default:%s): " defmd)
		 nil nil  defmd))
	    mandoku-base-dir))
	 (mduser (concat md "/user"))
	 (mandoku-ws-settings (expand-file-name (concat md "/KR-Workspace/Settings"))))
    (mkdir md t)
      ;; looks like we have to bootstrap the krp directory structure
      (progn
      ;; try to set to a size that still shows the minibuffer!
      (when (eq window-system 'w32)
	(set-frame-position (selected-frame)  100 0)
	(set-frame-size (selected-frame)
			;;# of chars per line
			80
			;;# of lines
			(/ (x-display-pixel-height)
			   (+ 4 (line-pixel-height))))
	(redisplay))
      (if (not mandoku-base-dir)
	  (setq mandoku-base-dir 
		(if (not (string= (substring md -1) "/"))
		    (concat md "/")
		  md)))
	      ;; see if we have a emacs init file, store it there!
      (let ((init-file (if (and user-init-file (file-exists-p user-init-file))
			   user-init-file
			 (if user-emacs-directory
			     (concat user-emacs-directory "/init.el")
			   (expand-file-name "~/.emacs.d/init.el")))))
	(with-current-buffer (find-file-noselect init-file)
	  (goto-char (point-min))
	  (unless (search-forward "mandoku-base-dir" nil t)
            (goto-char (point-max))
            (insert ";; --start-- added by mandoku installer\n")
            (insert "(setq mandoku-base-dir \"" mandoku-base-dir "\")\n")
            (insert ";; additional settings for mandoku: \n")
            (insert "(load (concat user-emacs-directory \"mandoku-init\"))\n")
            (insert "(mandoku-show-catalog)\n")
            (insert ";; --end-- added by mandoku installer\n")
            (save-buffer))
	  (kill-buffer)))
      ;; create the other directories
      (dolist (sd mandoku-subdirs)
	(mkdir (concat mandoku-base-dir sd) t))
      (mandoku-setup-dirvars)
      ;; check for workspace, but don't panic if it does not work out
      (ignore-errors
      (when (and (not (file-exists-p  mandoku-ws-settings))
		 (yes-or-no-p "No workspace found. 
It necessary to take full advantage of Mandoku, but requires a (free) Github account.  
If you do not currently have one, create one and come back, then you can download (clone) a workspace from GitHub. 
Otherwise, deal with Github later and continue without a workspace.
Do you want to download it now?"))
	(mandoku-get-extra "KR-Workspace")
	(mandoku-get-extra "KR-Gaiji")
	))
      (if (file-exists-p (expand-file-name "images" (concat md "/KR-Gaiji")))
	  (setq mandoku-gaiji-images-path (concat (expand-file-name "images" (concat md "/KR-Gaiji")) "/")))
      (setq mandoku-catalog (concat mandoku-meta-dir "mandoku-catalog.txt"))
      (unless (file-exists-p mandoku-catalog)
	(mandoku-update-catalog))
      (setq mandoku-titles-by-date
	    (if (file-exists-p (expand-file-name "krp-by-date.txt" mandoku-ws-settings))
		(expand-file-name "krp-by-date.txt" mandoku-ws-settings)
	      (expand-file-name "krp-by-date.txt" (concat md "/system"))))
      (if (not (file-exists-p mandoku-titles-by-date))
	  (url-copy-file "https://raw.githubusercontent.com/kanripo/KR-Workspace/master/Settings/krp-by-date.txt"  (expand-file-name "krp-by-date.txt" (concat md "/system"))))
      (setq mandoku-titles-file
	    (if (file-exists-p (expand-file-name "krp-titles.txt" mandoku-ws-settings))
		(expand-file-name "krp-titles.txt" mandoku-ws-settings)
	      (expand-file-name "krp-titles.txt" (concat md "/system"))))
      (if (not (file-exists-p mandoku-titles-file))
	  (url-copy-file "https://raw.githubusercontent.com/kanripo/KR-Workspace/master/Settings/krp-titles.txt"  (expand-file-name "krp-titles.txt" (concat md "/system"))))
      (setq mandoku-local-init-file (expand-file-name (concat user-emacs-directory "/mandoku-init.el")))
    (if (not (file-exists-p mandoku-local-init-file))
	(progn
	  (copy-file (expand-file-name "mandoku-init.el"
				       (file-name-directory
					(find-lisp-object-file-name 'mandoku-show-catalog (symbol-function 'mandoku-show-catalog))))
                     user-emacs-directory)
	  (load "mandoku-init")
	  ))
    (mandoku-read-titletables)
    (mandoku-write-local-text-list)
    )
  ;; load user settings in the workspace
  (when (file-exists-p mandoku-ws-settings)
    (ignore-errors 
      (add-to-list 'load-path mandoku-ws-settings)
      (mapc 'load (directory-files mandoku-ws-settings 't "^[^#].*el$")))))
  ;; if we do not have a credential helper, set one (is this stupid?
  (unless (equal "\"\"" mandoku-git-program)
    (add-hook 'git-commit-setup-hook 'mandoku-git-prepare-info)
    (unless (mandoku-git-config-get "credential" "helper")
      (mandoku-git-config-set "credential" "helper"
			    (if (eq window-system 'w32)
				"wincred"
			      (if (eq window-system 'mac)
				  "osxkeychain")))))
  ;; check for name and email, to avoid later problems
  (mandoku-git-prepare-info)
  ;; otherwise git will hang on windoof...
  (if (eq window-system 'w32)
      (setenv "GIT_ASKPASS" "git-gui--askpass"))
  (setq mandoku-initialized-p t))

(defun mandoku-show-local-init ()
  (interactive)
  (find-file mandoku-local-init-file))

;;; prepare user text
(defun mandoku-find-files-to-convert ()
  (interactive)
  (dired mandoku-work-dir "-alR")
  (dired-unmark-all-marks)
  (dired-mark-files-regexp "\\.txt")
  (define-key dired-mode-map "c" 'mandoku-operate-on-marked-files)
  (message "Please review the selected files.  If everything is correct, press C to continue")
  )  

(defun mandoku-operate-on-marked-files ()
  (interactive)
  (let ((files (dired-get-marked-files)))
    (mapc
     (lambda (ff) (mandoku-convert-file ff))
     files))
;  (define-key dired-mode-map "c" nil)
  (message "Concersion done! Press q to close this buffer.")
)
    
(defun mandoku-convert-file(file &optional encoding)
  (let ((enc (or encoding 'utf-8)))
    (with-current-buffer     (find-file-noselect file)
      (unless (memq buffer-file-coding-system (append (coding-system-eol-type 'raw-text) nil))
	(set-buffer-file-coding-system enc)
	(save-buffer))
    (kill-buffer)
  )))



;;;###autoload
(defun mandoku-search-user-text (search-for &optional search-dir)
  "This command searches through the texts located in `mandoku-work-dir'."
  (interactive 
   (let ((search-for (mapconcat 'char-to-string (mandoku-next-three-chars) "")))
     (list (read-string "Search in user files for: " search-for))))
  (let ((coding-system-for-read 'utf-8)
	(coding-system-for-write 'utf-8)
	(grep-find-ignored-files nil)
	(grep-find-ignored-directories nil)
	(sd (or search-dir mandoku-work-dir)))
    (if (fboundp 'ripgrep-regexp-x)
	(ripgrep-regexp search-for sd '("-ttxt"))
      (rgrep search-for "*.txt" sd nil))))

;;;###autoload
(defun mandoku-search-text (search-for)
  (interactive 
   (let ((search-for
	  (replace-regexp-in-string "\\([　-㏿！-￮]\\)" ""
				    (mapconcat 'char-to-string (mandoku-next-three-chars) ""))))
     (list (read-string "Search for: " search-for))))
  (let ((index-buffer (get-buffer-create "*temp-mandoku*"))
	(result-buffer (get-buffer-create "*Mandoku Index*"))
	sf)
  (unless mandoku-initialized-p
    (mandoku-initialize))
  (setq mandoku-search-for search-for)
  (when (derived-mode-p 'mandoku-view-mode)
    (setq mandoku-position (mandoku-position-at-point-internal))
    (set-marker mandoku-position-marker (point))
    )
  (if (or
       (string-match "[{\\*\\[]" search-for)
       (<= (list-length (setq sf (split-string search-for "[ ,　、。，]+"))) 1))
      (mandoku-grep-internal (mandoku-cut-string search-for) index-buffer result-buffer )
    (mandoku-multiple-search sf))
  ))

(defun mandoku-next-three-chars (&optional count)
  (let ((cnt (or count 6)) chr)
    (save-excursion
     (push (char-after) chr)
      (dotimes (c cnt)
	(mandoku-forward-one-char)
	(push (char-after) chr)))
    (reverse chr)))

;; (defun mandoku-forward-one-char ()
;;   (save-match-data
;;     (cond
;;      ((looking-at "&[^;]*;")
;;       (forward-char (- (match-end 0) (match-beginning 0))))
;;      ((looking-at mandoku-annot-drawer)
;;       (search-forward mandoku-annot-end)
;;       (mandoku-forward-one-char))
;;      ((looking-at "[:#	]")
;;       (forward-line 1)
;;       (mandoku-forward-one-char))
;;      ((looking-at "*")
;;       (forward-char 1)
;;       (mandoku-forward-one-char))
;;      ((looking-at "[ 　-㏿＀-￯\n¶]")
;;       (forward-char 1)
;;       (mandoku-forward-one-char))
;;      ((looking-at mandoku-regex)
;;       (forward-char (- (match-end 0) (match-beginning 0)))
;;       (mandoku-forward-one-char))
;;      ((looking-at mandoku-kanji-regex)
;;       (forward-char 1)
;;       )
;;      ;; ( t
;;      ;;   (mandoku-forward-one-char)
;;      ;;   ))
;;   )))

(defun mandoku-forward-one-char ()
	"this function moves forward one character, ignoring punctuation and markup
One character is either a character or one entity expression"
;	(interactive)
	(ignore-errors
	(save-match-data
	  (if (looking-at "&[^;]*;")
	      (forward-char (- (match-end 0) (match-beginning 0)))
	    (if (looking-at mandoku-annot-drawer)
		(progn
		  (search-forward mandoku-annot-end)
		  (forward-char 1))
	      (forward-char 1)))
	;; this skips over newlines, punctuation and markup.
	;; Need to expand punctuation regex [2001-03-15T12:30:09+0800]
	;; this should now skip over most ideogrph punct
	  (while (looking-at mandoku-regex)
	    (forward-char (- (match-end 0) (match-beginning 0))))
	  )
        (if (looking-at mandoku-annot-drawer)
            (progn
              (search-forward mandoku-annot-end)
              (forward-char 1))
          ;(forward-char 1)
          )
))

(defun mandoku-backward-one-char ()
	"this function moves backward one character, ignoring punctuation and markup
One character is either a character or one entity expression"
	(interactive)
	(ignore-errors
	(save-match-data
	(if (looking-at "&[^;]*;")
	    (backward-char (- (match-end 0) (match-beginning 0)))
	  (backward-char 1)
	)
	;; this skips over newlines, punctuation and markup.
	;; Need to expand punctuation regex [2001-03-15T12:30:09+0800]
	;; this should now skip over most ideogrph punct
	(while (looking-at mandoku-regex)
	  (backward-char (- (match-end 0) (match-beginning 0)))))
))


(defun mandoku-forward-n-characters (num)
	(while (> num 0)
		(setq num (- num 1))
		(message (number-to-string num))
		(mandoku-forward-one-char))
)

(defun mandoku-index-get-search-string ()
  "Get the search-string from the Index Buffer"
  (save-excursion
    (goto-char (point-min))
    (search-forward "
* " nil t)
    (car (split-string  (org-get-heading)))))

(defun mandoku-open-textfile ()
  "Looks at point and tries to open it as a mandoku link"
  (interactive)
  (when (string-match "KR" (thing-at-point 'symbol))
    (save-excursion
      (let ((bounds (bounds-of-thing-at-point 'symbol))
	    b2 page)
	(forward-thing 'symbol 1)
	(when (looking-at ":")
	    (forward-char)
	    (setq bounds (cons (car bounds) (cdr (bounds-of-thing-at-point 'symbol)))))
	(mandoku-link-open (buffer-substring-no-properties (car bounds) (cdr bounds)))))))

(defun mandoku-find-cit-from-region (beg end &optional step)
  (interactive "r")
  (let ((src (mandoku-cut-string
	      (mandoku-copy-clean beg end) 20))
	(step (or step 4))
	(search-strings ())
	(tmp ())
	j l n)
    (loop for j from 0 to (- (length src) 1) by step do
	  (push (char-to-string (elt src j)) search-strings))
    (if (>= (- (% (length src) step) 1) 2)
	(push (char-to-string (elt src (- (length src) 1))) search-strings))
    (loop for j from 0 to (- (length search-strings) 2) do
	  (push (format "%s.{1,6}%s" (elt search-strings (+ j 1)) (elt search-strings j))
		tmp))
    (mandoku-multiple-search tmp src)
    (message (format "%s" tmp))
))  

(defun mandoku-multiple-search (search-strings &optional src)
  (let ((index-buffer (get-buffer-create "*temp-mandoku*"))
	(result-buffer (get-buffer-create "*Mandoku Index*"))
	(sort-message "Sort: by (d)ate, text (i)d number or number of (h)its:\n")
	(mhash (make-hash-table :test 'equal))
	(cnt ())
	res loc)
    (mapc
     (lambda (search-for)
	(mandoku-prepare-index-buffer index-buffer search-for)
	(with-current-buffer index-buffer
	  (dolist (line (split-string (buffer-string) "\n" t))
	    ;; lets ignore the other versions for the moment..
	    (let ((tx (split-string line "\t" t)))
	      (when (or (< (length tx) 3) (equal (caddr tx) "n"))
		(setq loc (car (split-string (cadr tx) ":")))
		(puthash loc (cons (cons search-for line) (gethash loc mhash)) mhash))))))
     search-strings)
    (with-current-buffer result-buffer
      (erase-buffer)
      (dolist
	  (key (sort (mandoku-hash-keys-mhash mhash search-strings)
		     (lambda (k1 k2)
		       (> (length (gethash k1 mhash))
			  (length (gethash k2 mhash))))))
	(let ((txtid (car (split-string key "_")))
	      (juan (cadr (split-string key "_")))
	      (hits (length (gethash key mhash)))
	      )
	  (insert "\n** "
		txtid " "
		(mandoku-textid-to-title (car (split-string key "_")))
		" 第" (format "%d" (string-to-number juan))
		(format "巻 (%d)" hits)
		": \n"
		(format ":PROPERTIES:\n:ID: %s\n:TXTDATE: %s_%s\n:HITS: %3.3d\n:END:\n"
			key (gethash txtid mandoku-textdates) juan hits)
		(mapconcat
		 (lambda (v)
		   (let* ((lv (split-string (cdr v) "\t"))
			  (srch (car v))
			  (h1 (split-string (car lv) ","))
			  (loc (split-string (cadr lv) ":"))
			  (rest (caddr lv)))
		     (concat (format "*** [[mandoku:%s:%s%s::%s][%-16s]] "
				     (car loc) (cadr loc) (caddr loc) srch
				     (format "%s,%s:%s (%s)"
					     (cadr loc) (caddr loc) (cadddr loc) (car (last loc))))
			     (replace-regexp-in-string
			      (concat "\\(" srch "\\)")
			      " *\\1* "
			      (concat (cadr h1) (car h1))
			      )
			     )))
		 (sort (gethash key mhash)
		       (lambda (k1 k2)
			 (< (mandoku-transform-location k1)
			    (mandoku-transform-location k2))))
		 "\n"))))
      (goto-char (point-min))
      (insert (format "Mandoku Search Result:\n%s* %s" sort-message
		      (if src src
			(mapconcat 'identity search-strings ", "))))
      (mandoku-index-mode)
      (mandoku-refresh-images)
      (hide-sublevels 3)
      )
    ))

(defun mandoku-transform-location (loc)
  "Convert the location in the index to a sortable numeric representation"
  (let ((l (split-string (cadr (split-string (cdr loc) "\t")) ":")))
     (string-to-number
      (format "%s%3.3d%3.3d"
       (replace-regexp-in-string "\\([a-d]\\)" 
				 (lambda (rep)
				   (format "%s" (- (string-to-char rep) 96))) (cadr l))
       (string-to-number (caddr l))
       (string-to-number (cadddr l))))))


(defun mandoku-hash-keys-mhash (hash-table search-strings)
  ;; this is where I remove the unwanted matches...
  (let ((keys ()) res )
    (maphash
     (lambda (key value)
       (when (<= (length search-strings)
		 (length (setq res (remove-duplicates (mapcar 'car value) :test 'equal))))
       (push key keys))) hash-table)
    keys))


(defun mandoku-prepare-index-buffer (index-buffer search-string)
  ;; setup the buffer for the index results
  (set-buffer index-buffer)
  (setq buffer-read-only nil)
  (erase-buffer)
  (mandoku-search-internal search-string index-buffer)
  (goto-char (point-min))
  (when (looking-at "\n")
    (kill-line))
  (insert (substring search-string 0 1))
  ;; add the first char of searchstring to the index-buffer
  (while (re-search-forward "\n\\(.\\)" nil t)
    (replace-match (concat "\n" (substring search-string 0 1) (match-string 1))))
  (goto-char (point-min))
  ;; remove first, empty line
  ;; fix the image display
  (while (re-search-forward "<img[^>]+/images/\\([^>]+\\)./>" nil t)
    (if mandoku-gaiji-images-path
	(replace-match (concat "[[file:" mandoku-gaiji-images-path (match-string 1) "]]") t)
      (replace-match "⬤")))
  (goto-char (point-min))
  ;; just to be sure (the local index might have these..
  (while (re-search-forward "&\\([^;]+\\);" nil t)
    (if mandoku-gaiji-images-path
	(replace-match (concat "[[file:" mandoku-gaiji-images-path (match-string 1) ".png]]") t)
	(replace-match "⬤")))
  index-buffer)

(defun mandoku-grep-internal (search-string index-buffer result-buffer)
  (let ((coding-system-for-read 'utf-8)
	(coding-system-for-write 'utf-8)
	(the-buf (current-buffer))
	(org-startup-folded t)
	(mandoku-count 0))
    (progn
      (mandoku-prepare-index-buffer index-buffer search-string)
      (set-buffer result-buffer)
      (setq buffer-read-only nil)
      (erase-buffer)
      (set (make-local-variable 'mandoku-search-string) search-string)
      ;; switch to index-buffer and get the results
      (mandoku-read-index-buffer index-buffer result-buffer search-string)
      )))

(defun mandoku-search-internal (search-string index-buffer)
  (if mandoku-do-remote
      (progn
	(mandoku-search-remote search-string index-buffer)
	(let ((search-upper-case t))
	  (dolist (txtid  mandoku-local-index-list)
	    (with-current-buffer index-buffer
	      (goto-char (point-min))
	      (delete-matching-lines txtid))
	    ))
	(if mandoku-local-index-list
	    (let ((local-buffer (get-buffer-create "*local-mandoku*"))
		  tmpstr)
	      (mandoku-search-local search-string local-buffer)
	      (with-current-buffer local-buffer
		(goto-char (point-min))
		(while (re-search-forward "_\\([0-9]\\{3\\}\\):" nil t)
		  (replace-match ":\\1-"))
		(setq tmpstr (buffer-string))
		)
	      (with-current-buffer index-buffer
		(insert tmpstr))
	)))
    (mandoku-search-local search-string index-buffer))
)

(defun mandoku-search-local (search-string index-buffer)
;; find /tmp/index/SDZ0001.txt -name "97.idx.*" | xargs zgrep "^靈寳"
  (let ((coding-system-for-read 'utf-8)
	(coding-system-for-write 'utf-8)
	(search-char (string-to-char search-string)))
;; /tmp/index/4e/4e00/4e00.ZB6q.idx \\ 千賢人出現於世是故,成當有	ZB6q0001_001:010a:2:8:9
    (shell-command
     (concat mandoku-grep-command " -H -e " "\"^"
	     (substring search-string 1 )
	     "\" "
	     mandoku-index-dir
	     (substring (format "%04x" search-char) 0 2)
	     "/"
	     (format "%04x" search-char)
	     "/"
	     (format "%04x" search-char)
	     (if mandoku-search-limit-to-coll
		 (concat "." mandoku-search-limit-to-coll)
	       "")
	     "*.idx* | cut -d : -f 2-")
     index-buffer nil
     )
))


(defun mandoku-tabulate-index-buffer (index-buffer tablen)
  (switch-to-buffer-other-window index-buffer t)
  (let ((tabhash (make-hash-table :test 'equal))
	(m))
    (goto-char (point-min))
    (while (re-search-forward "^\\([^	]+\\)	\\([^	
]+\\)" nil t)
      (setq m (substring (match-string 2) 0 tablen))
      (if (gethash m tabhash)
	  (puthash m (+ (gethash m tabhash) 1) tabhash)
	(puthash m 1 tabhash)))
    tabhash))
;    (setq myList (mandoku-hash-to-list tabhash))))

    ;; (set-buffer result-buffer)
    ;; (dolist (x   
    ;; 	     (sort myList (lambda (a b) (string< (car a) (car b)))))
    ;;   (insert (format "* %s\t%s\t%d\n" (car x) (gethash (car x) mandoku-subcolls) (car (cdr x)))))))

(defun mandoku-index-insert-tablist (hashtable index-buffer)
  (let ((myList (mandoku-hash-to-list hashtable)))
    (set-buffer result-buffer)
    (dolist (x   
	     (sort myList (lambda (a b) (string< (car a) (car b)))))
      (insert (format "* %s %s\t%d\n\n" (car x) (gethash (car x) mandoku-subcolls) (car (cdr x)))))))

(defun mandoku-hash-to-list (hashtable)
  "Return a list that represent the HASHTABLE."
  (let (myList)
    (maphash (lambda (kk vv) (setq myList (cons (list kk vv) myList))) hashtable)
    myList
  )
)    
(defun mandoku-sum-hash (hashtable)
  "Return the sum of the HASHTABLE's value" 
  (let ((cnt 0))
    (maphash (lambda (kk vv) (setq cnt (+ cnt vv))) hashtable)
    cnt))

(defun mandoku-index-insert-result (search-string index-buffer result-buffer  &optional filter)
  (let (;(mandoku-use-textfilter nil)
      	(search-char (string-to-char search-string))
	(ngtab (if mandoku-ngram-n (mandoku-mi-index-buffer index-buffer search-string) nil))
	(mandoku-filtered-count 0))
    (set-buffer index-buffer)
    (setq buffer-file-name nil)
    ;; first: sort the result (after the filename)
    (sort-lines nil (point-min) (point-max))
    (goto-char (point-min))
    (while (re-search-forward
	    (concat "^\\([^,]*\\),\\([^\t]*\\)\t" filter  "\\([^\t \n]*\\)\t?\\([^\n]*\\)?$")
	 nil t )
      (let* ((pre (match-string 2))
	     (post (match-string 1))
	     (extra (match-string 4))
	     (location (split-string (match-string 3) ":" ))
	     (branches (remove "n" (split-string extra)))
	     (txtf (concat filter  (car location)
			   (when
			       branches
			     (concat "@" (mapconcat 'identity branches " ")))))
	     (txtid (concat filter (car (split-string (car location) "_"))))
	     (line (car (cdr (cdr location))))
	     (pag (car (cdr location)) ) 
	     (page (if (string-match "[-_]"  pag)
		       (concat (substring pag 0 (- (length pag) 1))
			       (mandoku-num-to-section (substring pag (- (length pag) 1))) line)
		     (concat
		      pag
		      line)))
	     (vol (mandoku-textid-to-vol txtid))
	     (tit (mandoku-textid-to-title txtid)))
	(set-buffer result-buffer)
	;; we ignore alternate versions at the moment
	;; [2017-02-09T10:52:54+0900] TODO: expose user option in index display to override this
	(unless (or (and branches (not mandoku-index-all-editions))
		    (and (mandoku-apply-filter txtid)
			 (mandoku-apply-datefilter txtid)))
	  (setq mandoku-filtered-count (+ mandoku-filtered-count 1))
	  (insert (format "** [[mandoku:%s:%s::%s][% 4s% 6s]]  % 10s%-30s  %s\n"
		  txtf page search-string  
		  (if vol
		      (concat vol ", ")
		    (or (ignore-errors (concat (number-to-string (string-to-number (cadr (split-string (car location) "_")))) ","))
			  ""))
		  (replace-regexp-in-string "^0+" "" page)
		  (replace-regexp-in-string "[\t\s\n+]" "" pre)
		  (replace-regexp-in-string "[\t\s\n+]" "" post)
		  (concat "  [[mandoku:meta:"
			    txtid
			    ":10][《" txtid
			    (when
				branches
			      (concat "@" (mapconcat 'identity branches " ")))
			    " "
			    (mandoku-cut-string tit 15 t)
			    "》]]")
			    ))
;; additional properties
	  (insert ":PROPERTIES:"
		    "\n:ID: " txtid
		    "\n:TXTDATE: " (gethash txtid mandoku-textdates)
		    (if mandoku-ngram-n
			(format "\n:NCNT: %5.5f" (mandoku-ngram-index-cnt (replace-regexp-in-string "[\t\s\n+]" "" (format "%s%c%s" pre search-char post)) ngtab mandoku-ngram-n))
		      "")
		    "\n:PAGE: " txtid ":" page
		    "\n:PRE: "  (concat (nreverse (string-to-list pre)))
		    "\n:POST: "
		    (replace-regexp-in-string "[\t\s\n+]" "" post)
		    "\n:END:\n"
		    ))
	    (set-buffer index-buffer)
;	    (setq mandoku-count (+ mandoku-count 1))
	    ))
      mandoku-filtered-count
      ))

(defun mandoku-ngram-index-cnt (s ngramhash &optional n)
  (let ((n (or n 2))
	(cnt 0)
	m j)
    (setq j 0)
    (while (< j  (- (length s) (- n 1)))
      (setq m (substring s j (+ j n)))
      (setq cnt (+ cnt (string-to-number (or (plist-get (gethash m ngramhash) :right) "0"))))
      (setq j (+ j 1)))
    cnt))
;; ngram-n

(defun mandoku-ngram-index-buffer (index-buffer search-string &optional n skip)
  "If skip it non-nil, the search-string itself will not added as ngram."
  (let ((n (or n 2))
	(ngramhash (make-hash-table :test 'equal))
	m s j l)
    (when mandoku-ngram-n
      (with-current-buffer index-buffer
	(goto-char (+ 1 (point-min)))
	(while (re-search-forward "^\\([^,]+\\),\\([^	]+\\)	\\([^	
]+\\)" nil t)
	  (setq l (length (match-string 2)))
	  (setq s (replace-regexp-in-string "\\[\\[file:[^\\[]*\\]\\]" "⬤"
					    (concat (match-string 2) (match-string 1))))
	  (setq j 0)
	  (while (< j  (- (length s) (- n 1)))
	    (unless (and skip (>= j l) (> (- (+ l (length search-string)) 1) j))
	      (setq m (substring s j (+ j n)))
	      (if (gethash m ngramhash)
		  (puthash m (+ (gethash m ngramhash) 1) ngramhash)
		(puthash m 1 ngramhash)))
					;(message m)
	    (setq j (+ j 1)))))
    ngramhash)))

(defun mandoku-calculate-mitab (ngtab)
    (let ((total 0)
	  (mitab (make-hash-table :test 'equal)) 
	  m1 m2 sum r1 l1)
      (maphash (lambda (key value)
		 (dolist (v (list :right :left))
		   (if (eq v :left)
		       (setq m1 (substring key 1 2)
			     m2 (substring key 0 1))
		     (setq m1 (substring key 0 1)
			   m2 (substring key 1 2)))
		   (setq r1 (gethash m1 mitab))
		   (if (setq l1 (plist-get r1 v))
		       (puthash m1 (setq r1 (plist-put r1 v (push (list m2 value) l1))) mitab)
		     (puthash m1 (setq r1 (plist-put r1 v (cons (list m2 value) l1))) mitab)))
		 (setq total (+ value total))
		 ) ngtab)
      (list mitab total)
      )
)

(defun mandoku-mi-index-buffer (index-buffer search-string)
  "Calculate the co-location probability for index buffer"
  (let* ((ngtab (mandoku-ngram-index-buffer index-buffer search-string 2 t))
	(mitabres (mandoku-calculate-mitab ngtab)) 
	(mitab (car mitabres))
	(total (cadr mitabres))
	(restab (make-hash-table :test 'equal))
	m1 r1 s1 sum)
    (maphash (lambda (key value)
	       (dolist (pl '(:right :left))
		 (setq sum (apply '+ (mapcar 'cadr (plist-get value pl))))
		 (dolist (v (remove nil (plist-get value pl)))
		   (setq m1 (if (eq pl :right)
				(concat key (car v))
			      (concat (car v) key)))
		   (setq s1 (format "%3.3f" (/ (coerce (cadr v) 'float) sum)))
		   (setq r1 (plist-put (gethash m1 restab) pl s1))
		   (puthash m1 r1 restab)
		 ))
	       ) mitab)
    restab))
  
(defun mandoku-read-index-buffer (index-buffer result-buffer search-string)
  (let* (
	(mandoku-count 0)
	(mandoku-filtered-count 0)
	(loc-mat-src (format "%-15s %-36s%s" "Location" "Match" "Source"))
	(sort-message
	 (concat "Sort: by (d)ate, (p)receding or (f)ollowing character, text (i)d number"
		 (if mandoku-ngram-n "or (n)gram count.\n" ".\n")))
	(date-message "")
      	(search-char (string-to-char search-string))
	(tab (mandoku-tabulate-index-buffer index-buffer 4))
	(cnt (mandoku-sum-hash tab)))
    (if (and (not (= 0 mandoku-index-display-limit)) (> cnt mandoku-index-display-limit))
;    (if nil
	(mandoku-index-insert-tablist tab result-buffer)
      (setq mandoku-filtered-count
	    (mandoku-index-insert-result search-string index-buffer result-buffer "")))
      (switch-to-buffer-other-window result-buffer t)
      (goto-char (point-min))
;      (insert (format "There were %d matches for your search of %s:\n"
;       mandoku-count search-string))
      (if (equal mandoku-use-textfilter t)
	  (insert (format "Active Filter: %s , Matches: %d (Press 't' to temporarily disable the filter)\n%s\n* %s (%d/%d)\n%s" 
			  (mapconcat 'mandoku-active-filter mandoku-textfilter-list "")
			  mandoku-filtered-count
			  loc-mat-src
			  search-string
			  mandoku-filtered-count cnt sort-message))
	(if (> cnt mandoku-index-display-limit )
	    (insert (format "Too many results!\nDisplaying only overview\n* %s (%d)\nCollection\tMatches\n" search-string cnt ))

;	    (insert (format "Too many results: %d for %s! Displaying only overview\nCollection\tMatches\n" cnt search-string))
	  (insert (format "Mandoku search result%s\n%s%s\n* %s (%d)\n" date-message sort-message loc-mat-src search-string cnt))
	)
	)
      (mandoku-index-mode)
      (mandoku-refresh-images)
      (hide-sublevels 2)
      (replace-buffer-in-windows index-buffer)
;      (kill-buffer index-buffer)
))

(defun mandoku-textid-to-vol (txtid) nil)

(defun mandoku-textid-to-title (txtid) 
;  (list txtid (gethash txtid mandoku-titles)))
  (gethash txtid mandoku-titles))

(defun mandoku-meta-textid-to-file (txtid &optional page)
  (if mandoku-catalogs-alist
      (let* ((repid (car (split-string txtid "[0-9]")))
	     (subcoll (mandoku-subcoll txtid ))
	     )
	(if (assoc subcoll mandoku-catalogs-alist)
	    (cdr (assoc subcoll mandoku-catalogs-alist))
	  (cdr (assoc (substring subcoll 0 -1) mandoku-catalogs-alist))))
    (user-error "No catalog file found.  Please clone KR-Catalog from the Kanseki repository")))
      


(defun mandoku-get-outline-path (&optional pnt)
  "this includes the first upward heading"
  (let ((p (or pnt (mandoku-start)))
	  olp)
    (save-excursion
      (goto-char p)
      (if (org-before-first-heading-p)
	  (list "")
	  (outline-previous-visible-heading 1)
	  (when (looking-at org-complex-heading-regexp)
	    (push
	     (if (not (org-match-string-no-properties 4))
	       ""
	       (org-trim
		   (replace-regexp-in-string org-bracket-link-regexp "\\3"
		   (replace-regexp-in-string
		    ;; Remove statistical/checkboxes cookies
		    "\\[[0-9]+%\\]\\|\\[[0-9]+/[0-9]+\\]\\|¶" ""
		    (org-match-string-no-properties 4)))))
		  olp))
	  (while (org-up-heading-safe)
	    (when (looking-at org-complex-heading-regexp)
	      (push
	       (if (not (org-match-string-no-properties 4))
		   ""
		 (mandoku-cut-string 
		     (org-trim
		      (replace-regexp-in-string org-bracket-link-regexp "\\3"
		     (replace-regexp-in-string
		      ;; Remove statistical/checkboxes cookies
		      "\\[[0-9]+%\\]\\|\\[[0-9]+/[0-9]+\\]\\|¶" ""
		      (org-match-string-no-properties 4))))))
		    olp)))
	  olp))))


(defun mandoku-cut-string (s &optional len ell)
  (let ((l (or len mandoku-string-limit)))
    (if (< l (length s)  )
	(if ell
	    (concat (substring s 0 (- l 1)) "…")
	  (substring s 0 l))
    s))
)

(defun manoku-index-no-filter ()
  "Temporarily displays the search result without applying a filter"
  (interactive)
  (save-match-data 
  (let ((mandoku-use-textfilter nil)
	(index-buffer (get-buffer "*temp-mandoku*"))
	(result-buffer (current-buffer))
	(search-string (progn
			 (goto-char (point-min))
			 (re-search-forward "^\* \\([^ ]*\\) (")
			 (match-string 1))))
    (set-buffer result-buffer)
    (setq buffer-read-only nil)
    (erase-buffer)
    (mandoku-read-index-buffer index-buffer result-buffer search-string))))

(defun mandoku-apply-datefilter (textid)
  ;(if mandoku-datefilter
   (< mandoku-datefilter (string-to-number (gethash textid mandoku-textdates)))
   );)

(defun mandoku-apply-filter (textid)
  "Apply a filter to the search results."
    (if (equal mandoku-use-textfilter t)
	(let ((test t))
	(dolist (f mandoku-textfilter-list)
	  (if (get f :active)
	      (if (gethash textid (symbol-value f))
		  (setq test nil))))
	test)
    ))

(defun mandoku-active-filter (f)
;; rewrite as mapping function
    (if (get f :active)
	(if (get f :filename)
	    (format "[[file:%s][%s]] " 
		    (get f :filename) 
		    (get f :name))
	  (get f :name)
	  )
      nil))

(defun mandoku-read-textfilter	 (filename )
  "Reads a new textfilter and adds it to the list of textfilters"
  (when (file-exists-p filename)
    (let ((fn (file-name-sans-extension (file-name-nondirectory filename))))
      (eval (read (concat "(setq tab-" (file-name-sans-extension (file-name-nondirectory filename)) " (make-hash-table :test 'equal))")))
      (eval (read (concat "(put 'tab-" fn " :name \042" fn "\042)")))
      (eval (read (concat "(put 'tab-" fn " :filename \042" filename "\042)")))
      (eval (read (concat "(put 'tab-" fn " :active  t )")))
      (with-temp-buffer
        (let ((coding-system-for-read 'utf-8)
              textid)
          (insert-file-contents filename)
          (goto-char (point-min))
          (while (re-search-forward "^\\([A-z0-9]+\\)\s+\\([^\s\n]+\\)" nil t)
	    (eval (read (concat "(puthash (match-string 1) (match-string 2) tab-" fn ")"))))))
      (eval (read (concat "(add-to-list 'mandoku-textfilter-list 'tab-" fn ")"))))))
      

(defun mandoku-make-text-filter-from-search-results ()
  "Called from a *Mandoku Index* buffer, creates a textfilter
that includes all text ids of texts that matched here."
  (interactive)
  (when (eq major-mode 'mandoku-index-mode)
    (let* ((txtids (org-property-values "ID"))
	  (search (save-excursion
		    (goto-char (point-min))
		    (search-forward "* ")
		    (car (mandoku-get-header-item ))))
	  (filtername  (read-string (concat "Name for this filter (default:" search "): ") search))
	  (fn (concat mandoku-filters-dir filtername ".txt" )))
      (with-current-buffer (find-file-noselect fn)
	(insert ";;" (current-time-string) "\n")
	(dolist (axx txtids)
	  (insert axx " " (mandoku-textid-to-title axx) "\n"))
	(save-buffer))
      (when (yes-or-no-p "Load the new text filter?")
	(mandoku-read-textfilter fn)
	(setq mandoku-use-textfilter t))
      (message "%s %s" search fn)
    )
))

(defun mandoku-make-textfilter ()
  "Creates a new textfilter and adds it to the list of textfilters"
)


(defun mandoku-num-to-section (num)
  "Converts the number codes used in the index to the conventionally used values abc"
  (format "%c" (+ (string-to-number num) 96)))

(defun mandoku-section-to-num (sec)
  "Converts the number codes used in the index to the conventionally used values abc"
  (- (string-to-char sec) 96))


(defun mandoku-parse-pno (s)
" parse a pagenumber s format is pagenumber:line or maybe 462a12"
    (let
	((page (if (posix-string-match ":" s)
		   (car (split-string s ":"))
		 (if (posix-string-match "[a-z]" s)
		     (substring s 0 (+ 1 (length (car (split-string s "[a-z]")))))
		   s)))
	 (line (if (posix-string-match "[a-z:]" s)
		   (string-to-number (car (cdr  (split-string s "[a-z:]"))))
		 0)))
     (string-to-number (format "%s%s%2.2d" (substring page 0 (- (length page) 1) ) (mandoku-section-to-num (substring page (- (length page) 1) ))  line))
      ))

(defun mandoku-execute-file-search (s)
  "Go to the line indicated by s format is pagenumber:line or maybe
462a12. To disambiguate from other matches, a '>' character will
be appended. Optionally, a search term is appended after a
separator '::'. A character number can also be indicated with a
separator ':'. 14a03:1::或 will thus go go page 14a, line 3,
first character and highlight '或'."
  (when (or (eq major-mode 'mandoku-view-mode)
	  (eq major-mode 'mandoku-tls-view-mode)
	  (eq major-mode 'org-mode))
    (let* (
	   (page
	    (if (equal (string-to-char s) ?#)
	       (concat "^[ \t]*:CUSTOM_ID:[ \t]+"
		       (regexp-quote (substring s 1)) "[ \t]*$")
	    (if (posix-string-match "[a-h]" s)
		     (substring s 0 (+ 1 (length (car (split-string s "[a-o]")))))
	      (if (posix-string-match "l" s)
		   (car (split-string s "l"))
		s))))
	   (line (if (posix-string-match "[a-o]." s)
		     (string-to-number (car (cdr  (split-string (car (split-string s "::")) "[a-o]"))))
		   0))
	   (char (string-to-number  (or (cadr (split-string s ":")) "")))
	   (search (if (posix-string-match "::" s)
		       (car (cdr (split-string s "::")))
		     nil)))
      (goto-char (point-min))
      (if (equal (string-to-char s) ?#)
	  (re-search-forward page nil t)
	(re-search-forward (concat page ">") nil t))
    (while (< -1 line)
      (re-search-forward "¶" nil t)
      (+ (point) 1)
      (setq line (- line 1)))
    ;; not sure about this...
    (goto-char (+ (point) char))
    (if (equal (string-to-char s) ?#)
	(org-back-to-heading t)
      (beginning-of-line-text))
    (if search
	(progn
	  (hi-lock-mode t)
	  ;; FIXME: need to construct a true regex here!
	  (highlight-regexp
	   (mapconcat 'char-to-string
		      (string-to-list search) (concat "\\(" mandoku-regex "\\)?")))
	  ;; (message 	   (mapconcat 'char-to-string
	  ;; 	      (string-to-list search) (concat "\\(" mandoku-regex "\\)?")))
	  )
    ))
  ;; return t to indicate that the search is done.
    t))

(defun mandoku-position-at-point ()
  (interactive)
  (message (mandoku-position-at-point-formatted)))

(defun mandoku-position-at-point-formatted ()
  (let ((p (mandoku-position-at-point-internal)))
    (if p
	(format "%s %sp%s%2.2d" (nth 1 p) (if (mandoku-get-vol) (concat (mandoku-get-vol) ", ") "") (car (cdr (split-string (nth 2 p) "-"))) (nth 3 p))
      " -- ")
    ))
(defun mandoku-position-with-char (&optional pnt arg)
  "returns textid edition page line char"
  (let* ((p (or pnt (mandoku-start)))
	 (location (cdr (cdr (mandoku-position-at-point-internal p arg ))))
	 (ch (mandoku-charcount-at-point-internal p))
	 (loc-format (concat (car location) (format "%2.2d" (car (cdr location))))))
    (concat loc-format "-" (format "%2.2d"  ch))))


(defun mandoku-position-at-point-internal (&optional pnt arg)
  "This will always give the position in the base edition, except when forced to use <pb: with arg."
  (save-excursion
    (let ((p (or pnt (point)))
          (buffer-invisibility-spec nil)
	  (pb (if arg 
		  "<pb:"
		(or (if 
		      (progn 
			(goto-char (point-min))
			(re-search-forward "<md:" (point-max) t)) 
		      "<md:")
		  "<pb:")))
	  )
      (goto-char p)
      (if (re-search-backward pb nil t)
	  (if (re-search-forward ":\\([^_]*\\)_\\([^_]*\\)_\\([^_>]*\\)>" nil t)
	      (let ((textid (match-string 1))
		    (ed (match-string 2))	
		    (page (match-string	3))
	    (line -1))
	    (while (and
		    (< (point) p )
		    (re-search-forward "¶" (point-max) t))
	      (setq line (+ line 1)))
	    (list textid ed page line (mandoku-charcount-at-point-internal p))))
	(list " -- " " -- " " -- " 0 0))
      )))

(defun mandoku-charcount-at-point-internal (&optional pnt)
"return the number of characters on this line up to and including
the character at point, ignoring non-Kanji characters"
  (save-excursion
    (let* ((p (or pnt (point)))
	   (buffer-invisibility-spec nil)
	   (begol (or (save-excursion (goto-char p) (re-search-backward "¶" nil t ))
		      p))
	   (bs (buffer-substring-no-properties begol p))
	   (charcount 0))
      (goto-char begol)
      (while (and (< charcount 50 )
		  (< (point) p ))
	(mandoku-forward-one-char)
	(setq charcount (+ charcount 1)))
      charcount
)))

;; image handling

(defun mandoku-find-image (path rep)
  "open the file referenced through image path. Check if available locally, otherwise get from remote image server"
    (if (file-exists-p (concat mandoku-image-dir (cadr path)))
	(find-file-other-window (concat mandoku-image-dir (cadr path)))
    ;; need to retrieve the file and store it there to open it
      (let* (
	     (buffer (concat mandoku-image-dir (cadr path)))
	     (imgbuffer (url-retrieve-synchronously (concat (car path) (cadr path )))))
	(unless (file-directory-p (file-name-directory buffer))
	  (make-directory (file-name-directory buffer) t))
	(with-current-buffer (get-buffer-create buffer)
	  (setq buffer-file-name buffer)
	  (unwind-protect
	      (let ((data (with-current-buffer imgbuffer
			    (goto-char (point-min))
			    (search-forward "\n\n")
			    (buffer-substring (point) (point-max)))))
					;(insert-image (create-image data nil t))
		(insert data)
		(save-buffer))
	    (kill-buffer imgbuffer))
	  (kill-buffer)))
	(find-file-other-window (concat mandoku-image-dir (cadr path)))
	))

(defun mandoku-get-imglist (f)
  ;; stopgap workaround, the ZB files are not supported...
  (if (equal "ZB" (substring f 0 2))
      "/tmp/noimg.txt"
  ;; this will always get the imglist from the kanripo repo.  Do we want that???
    (let ((imglist-rep (format mandoku-gh-imglist-template mandoku-gh-rep (car (split-string f "_")) f "txt"))
	  (imglist-user (format mandoku-gh-imglist-template mandoku-gh-user (car (split-string f "_")) f "txt"))
	  (imgcfg-rep (format mandoku-gh-imglist-template mandoku-gh-rep (car (split-string f "_")) "imginfo" "cfg"))
	  (imgcfg-user (format mandoku-gh-imglist-template mandoku-gh-user (car (split-string f "_")) "imginfo" "cfg"))
	  (ifile (format "%simglist/%s.txt" mandoku-temp-dir f))
	  (imgcfg (format "%simglist/%s-img.cfg" mandoku-temp-dir (car (split-string f "_")))))
    (unless (file-exists-p ifile)
      (with-current-buffer (find-file-noselect ifile)
	(if (url-file-exists-p imglist-user)
	    (url-insert-file-contents imglist-user)
	  (url-insert-file-contents imglist-rep))
	(save-buffer)))
    (unless (file-exists-p imgcfg)
      (with-current-buffer (find-file-noselect imgcfg)
	(if (url-file-exists-p imgcfg-user)
	    (url-insert-file-contents imgcfg-user)
	  (url-insert-file-contents imgcfg-rep))
	(save-buffer)))
    (list ifile imgcfg))
  ))

(defun mandoku-open-image-at-page (arg &optional il)
  "this will first look for a function for this edition, then browse the image index"
  (interactive "P")
  (let* ((f  (file-name-sans-extension (file-name-nondirectory (buffer-file-name))))
	 (rep (car (split-string f "[0-9]")))
	 ;https://raw.githubusercontent.com/kanripo/KR5a0001/_data/imglist/KR5a0001_002.txt
	 ;; hardcoded --
	 (imglist (or il (mandoku-get-imglist f)))
	 (p (mandoku-position-at-point-internal (point) ))
	 ;; if function exists, use that, otherwise look for image in imglist, if not available: nil
	 (path  (if (file-exists-p (car imglist))
		    (mandoku-get-image-path-from-index p imglist)
		  (ignore-errors  
		    (funcall (intern (concat "mandoku-" (downcase (nth 1 p))  "-page-to-image")) p )))))
    (if path
	(progn
	  (if (= (count-windows) 1)
	      (split-window-horizontally 55))
	  (mandoku-find-image path rep))
      (message "No facsimile available."))))


(defun mandoku-get-editions-from-index (il)
  (let* ((eds (list))
	(fn (nth (- (length (split-string (cadr il) "/")) 1) (split-string (cadr il) "/")))
	(thebuffer (get-buffer-create (concat " *mandoku-img-" fn)))
	)
    (with-current-buffer thebuffer 
      (let ((coding-system-for-read 'utf-8))
	(erase-buffer)
	(insert-file-contents (cadr il))
	(goto-char (point-min))
	  (while (re-search-forward "^\\([^=
]+\\)=" nil t)
	    (add-to-list 'eds (match-string 1))) ))
eds
))

(defun mandoku-imglist-get-prefix (il ed)
  "Get the prefix path for the edition ed out of the imagelist in the cadr of il"
  (let* (
	(fn (nth (- (length (split-string (cadr il) "/")) 1) (split-string (cadr il) "/")))
	(thebuffer (get-buffer-create (concat " *mandoku-img-" fn)))
	eds
	)
    (with-current-buffer thebuffer 
      (let ((coding-system-for-read 'utf-8))
	(erase-buffer)
	(insert-file-contents (cadr il))
	(goto-char (point-min))
	  (while (re-search-forward "^\\([^=
]+\\)=\\([^
]+\\)" nil t)
	    (add-to-list 'eds `(,(match-string 1) . ,(match-string 2) )) )))
   (cdr (assoc ed eds))
))


(defun mandoku-get-image-path-from-index (loc il &optional ed)
  "Read the image index for this file if necessary and return a path to the requested image"
  (let* ((f  (file-name-sans-extension (file-name-nondirectory (buffer-file-name))))
	 (lastpg "99")
	 (pg (nth 2 loc))
	 (line (nth 3 loc))
	 (fn (nth (- (length (split-string (car il) "/")) 1) (split-string (car il) "/")))
	 (eds (mandoku-get-editions-from-index il))
	 ;; no need to ask if there is only one edition
	 (ed (or ed
		 mandoku-preferred-edition
		 (if (= (length eds) 1) 
			(car eds)
		   (ido-completing-read "Edition: " (mandoku-get-editions-from-index il) nil t))))
	 (pref (mandoku-imglist-get-prefix il ed))
	 )

      (with-current-buffer (get-buffer-create (concat " *mandoku-img-" fn))
      (let ((coding-system-for-read 'utf-8))
	(erase-buffer)
	(insert-file-contents (car il))
	(sort-numeric-fields 1 (point-min) (point-max))
	(goto-char (point-max))
	(re-search-backward (concat "^" pg "\\([0-9][0-9]\\)\t\\([^\t\n]+\\)\t\\([^\t\n]+\\)") nil t)
	(message (match-string 0))
	(if (match-string 1)
	    (progn
	      (setq lastpg (string-to-number (match-string 1)))
	      (while (and (< (nth 3 loc) lastpg)  
			  (re-search-backward (concat "^" pg "\\([0-9][0-9]\\)\t\\([^\t\n]+\\)\t\\([^\t\n]+\\)") nil t))
		(setq lastpg (string-to-number (match-string 1)))))
	  (goto-char (point-min)))
	(next-line)
	(re-search-backward (concat "\t" ed " [^\t]+\t\\(.*\\)$") nil t)
	(list pref (match-string 1))
	))))




(defun mandoku-make-image-path-index (&optional il )
  "Add the current edition to an index file"
  (let* ((f  (file-name-sans-extension (file-name-nondirectory (buffer-file-name))))
	(imglist (or il (concat (substring (file-name-directory (buffer-file-name)) 0 -1) ".wiki/imglist/" f ".txt"))))
  (save-excursion 
    (goto-char (point-min))
    (while (re-search-forward "<pb:\\([^_]*\\)_\\([^_]*\\)_\\([^_>]*\\)>" nil t)
      (let ((ed (match-string 2))
	    (p (match-string 3))
	    (px (mandoku-position-at-point-internal (point))))
      (write-region (format "%s%2.2d\t%s %s\t%s\n"  (nth 2 px)  (nth 3 px) ed p 
			    (downcase (format "%s/%s/%s-%s.jpg" (nth 0 px) ed ed p)))
		    nil imglist t)
)))))

(defun mandoku-make-img-index (&optional path)
  "Generate an image index for all editions in path or, if not given, in the current directory"
  (let ((p (or path (file-name-directory (buffer-file-name))))
	(br (mandoku-get-branches)))
    (mkdir (concat (substring p 0 -1) ".wiki/imglist") t)
;    (dolist (b br)
;      (if (> 1 (length b))
;	  nil
	(progn
;      (or (string-match "^*" b)
;	  (mandoku-switch-version b))
      (dolist (file (directory-files p t ".txt"))
	(with-current-buffer (find-file-noselect file)
	(mandoku-make-image-path-index)
	(kill-buffer))))))


(defun mandoku-img-to-text (arg)
  "when looking at an image, try to find the corresponding text location"
  (interactive "P")
  (let* ((pb (file-name-sans-extension (file-name-nondirectory (buffer-file-name))))
         (this (split-string pb "_")))
	  (if (file-exists-p (concat mandoku-text-dir "dzjy/" (elt this 1) "/" (elt this 1 ) ".txt"))
	      (find-file-other-window (concat mandoku-text-dir "dzjy/" (elt this 1) "/" (elt this 1 ) ".txt"))
	    (find-file-other-window (concat mandoku-text-dir "dzjy-can/" (elt this 1) "/" (elt this 1 ) ".txt")))
	  (goto-char (point-min))
	  (message pb)
	  (search-forward (concat "<pb:" pb))))


(defun mandoku-cit-format (location)
;; FIXME imlement citation formats for mandoku
  (format "%s %s" (mandoku-get-title)  location)
)


;; (defun mandoku-textid-to-filename (coll textid page)
;; "given a textid, a collection id and a page, return the file that contains this page"
;; (funcall (intern (concat "mandoku-" coll "-textid-to-file")) textid page))




;; mandoku-view-mode

(defvar mandoku-view-mode-map
  (let ((map (make-sparse-keymap)))
;    (define-key map "e" 'view-mode)
;    (define-key map "a" 'redict-get-line)
         map)
  "Keymap for mandoku-view mode"
)


(define-derived-mode mandoku-view-mode org-mode "mandoku-view"
  "a mode to view mandoku files
  \\{mandoku-view-mode-map}"
  (setq case-fold-search nil)
  (setq header-line-format (mandoku-header-line))
  (set (make-local-variable 'tab-width) 25)
;; editions will hold a list of editions, for which a facsimile exists
  (set (make-local-variable 'editions) nil)
;; this will be populated with the list of paths to facsimile of the pages in this file
  (set (make-local-variable 'facsimile-list) nil)
  (mandoku-add-comment-face-markers)
  (mandoku-hide-p-markers)
  (mandoku-display-inline-images)
  (add-to-invisibility-spec 'mandoku)
  (local-unset-key [menu-bar Org])
  (local-unset-key [menu-bar Tbl])
  (easy-menu-add mandoku-md-menu mandoku-view-mode-map)
  (add-hook 'after-save-hook 'mandoku-add-to-for-commit-list nil t)
  ;;;; this affects all windows in the frame, do not want this..
  ;; (if (string-match "/temp/" (buffer-file-name) )
  ;;     (set-background-color "honeydew"))
;  (mandoku-install-version-files-menu)
					;  (view-mode)
  (set (make-local-variable 'org-startup-folded) 'nofold)
)
;; let's add the menu to the top menu which is always available
(easy-menu-add-item
 nil '("Tools")
  '("Mandoku"
     ["Show catalog" mandoku-show-catalog t]
     ["Search Texts" mandoku-search-text t]
     ["Search Titles" mandoku-search-titles t]
     ["Search My Files" mandoku-search-user-text t]
     ["Reload title table" mandoku-read-titletables t]
     )
 "Spell Checking")
(easy-menu-add-item nil '("Tools") '("----") "Spell Checking")



(defun mandoku-toggle-visibility ()
  (interactive)
  (if buffer-invisibility-spec
      (progn
	(visible-mode 1)
	(org-remove-inline-images))
    (progn 
	(visible-mode -1)
	(mandoku-display-inline-images)))
  (if buffer-invisibility-spec
      (easy-menu-change
	 '("Mandoku") "Display"
	 (list  ["Show markers" mandoku-toggle-visibility t]))
    (easy-menu-change
	 '("Mandoku") "Display"
	 (list ["Hide markers" mandoku-toggle-visibility t])))
  (redraw-display)
)

  
      
(defun mandoku-header-line ()
  (let* ((fn (ignore-errors (file-name-sans-extension (file-name-nondirectory (buffer-file-name )))))
	 (textid (if fn
		     (car (split-string fn "_"))
		   "No Name")))
    (list 
     (concat " " textid " " (mandoku-get-title)  ", " (mandoku-get-juan) " -  ")
     '(:eval  (mandoku-cut-string (mapconcat 'identity (mandoku-get-outline-path) " / ") 20))
     " "
     '(:eval (mandoku-position-at-point-formatted))
     " BR: "
     '(:eval (mandoku-get-current-branch))
     " "
     )
     ))


;(setq mandoku-hide-p-re "\\(?:<[^>]*>\\)\\|¶\n\\|¶")
;(setq mandoku-hide-p-re "\\(?:<[^>]*>\\)\\|¶")
(setq mandoku-hide-p-re "\\(<[pm][db]\\)\\([^_]+_[^_]+_\\)\\([^>]+>\\)\\|¶")
(defun mandoku-hide-p-markers ()
  "add overlay 'mandoku to hide/show special characters "
  (save-match-data
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward mandoku-hide-p-re nil t)
	(if (match-beginning 2)
	    (overlay-put (make-overlay (- (match-beginning 2) 2) (match-end 2) (current-buffer) t) 'invisible 'mandoku)
	  (if (match-beginning 1)
	      (overlay-put (make-overlay (match-beginning 1) (match-end 1) (current-buffer) t) 'invisible 'mandoku)
	    (overlay-put (make-overlay (match-beginning 0) (match-end 0) (current-buffer) t) 'invisible 'mandoku)))
	)
      )))
;; faces
;(set-face-attribute 'mandoku-comment-face nil :height 150)
;(set-face-attribute 'mandoku-comment-face nil :background "yellow1")

(setq mandoku-comment-face-markers-re "\\(([^)]+\\)")

(defface mandoku-comment-face
   '((((class grayscale) (background light))
      (:foreground "DimGray" :bold t :italic t))
     (((class grayscale) (background dark))
      (:foreground "LightGray" :bold t :italic t))
     (((class color) (background light)) (:foreground "dark magenta" :height 0.85))
     (((class color) (background dark)) (:foreground "OrangeRed" :height 0.85))
     (t (:bold t :italic t)))
   "Font Lock mode face used to highlight comments."
   :group 'mandoku-faces)

(defun mandoku-add-comment-face-markers ()
  (save-match-data
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward mandoku-comment-face-markers-re nil t)
	(if (match-beginning 1)
	    (overlay-put (make-overlay (match-beginning 1) (+ 1 (match-end 1))) 'face 'mandoku-comment-face)
	  (overlay-put (make-overlay (match-beginning 0) (match-end 0)) 'face 'mandoku-comment-face))))
    ))
(setq mandoku-gaiji-re "&\\(KR[^;]+\\);")

(defun mandoku-display-inline-images (&optional include-linked refresh beg end)
  "Display the character entities as inline images.
(mostly borrowed from org-display-inline-images).
When REFRESH is set, refresh existing images between BEG and END.
This will create new image displays only if necessary.
BEG and END default to the buffer boundaries."
  (interactive "P")
  (when (and mandoku-gaiji-images-path (display-graphic-p))
    (unless refresh
      (org-remove-inline-images)
      (if (fboundp 'clear-image-cache) (clear-image-cache)))
    (save-excursion
      (save-restriction
	(widen)
	(setq beg (or beg (point-min)) end (or end (point-max)))
	(goto-char beg)
	(let ((re mandoku-gaiji-re)
	      (case-fold-search t)
	      old file ov img type attrwidth width)
	  (while (re-search-forward re end t)
	    (setq old (get-char-property-and-overlay (match-beginning 1)
						     'org-image-overlay)
		  file (expand-file-name
			(concat mandoku-gaiji-images-path (match-string 1) ".png"))) 
	    (when (image-type-available-p 'imagemagick)
	      (setq attrwidth (if (or (listp org-image-actual-width)
				      (null org-image-actual-width))
				  (save-excursion
				    (save-match-data
				      (when (re-search-backward
					     "#\\+attr.*:width[ \t]+\\([^ ]+\\)"
					     (save-excursion
					       (re-search-backward "^[ \t]*$\\|\\`" nil t)) t)
					(string-to-number (match-string 1))))))
		    width (cond ((eq org-image-actual-width t) nil)
				((null org-image-actual-width) attrwidth)
				((numberp org-image-actual-width)
				 org-image-actual-width)
				((listp org-image-actual-width)
				 (or attrwidth (car org-image-actual-width))))
		    type (if width 'imagemagick)))
	    (when (file-exists-p file)
	      (if (and (car-safe old) refresh)
		  (image-refresh (overlay-get (cdr old) 'display))
		(setq img (save-match-data (create-image file type nil :width width)))
		(when img
		  (setq ov (make-overlay (match-beginning 0) (match-end 0)))
		  (overlay-put ov 'display img)
		  (overlay-put ov 'face 'default)
		  (overlay-put ov 'org-image-overlay t)
		  (overlay-put ov 'modification-hooks
			       (list 'org-display-inline-remove-overlay))
		  (push ov org-inline-image-overlays))))))))))



;; (define-key mandoku-view-mode-map
;;   "C-ce" 'view-mode)




(add-hook 'org-execute-file-search-functions 'mandoku-execute-file-search)

;; formatting

;; (defun mandoku-format-file (file)
;; (interactive)
;; (with-current-buffer
;; (goto-char (point-min))
;; (while (re-search-forward "。\\([^¶\n\t]\\)" nil t)
;;   (replace-match "。
;; " (match-data))
;; ))

(defun mandoku-helm-index-candidates ()
  "Helm source for index"
  (let (l
	(filter "")
	(search-string mandoku-search-for))
    (with-current-buffer (get-buffer-create "*temp-mandoku*")
      (goto-char (point-min))
      ;(setq search-string (buffer-substring-no-properties 1 2))
      (while (re-search-forward
	      (concat "^\\([^,]*\\),\\([^\t]*\\)\t" filter  "\\([^\t \n]*\\)\t?\\([^\n]*\\)?$")
	      nil t )
	(let* ((pre (match-string 2))
	       (post (match-string 1))
	       (extra (match-string 4))
	       (location (split-string (match-string 3) ":" ))
	       (branches (remove "n" (split-string extra)))
	       (txtf (concat filter  (car location)
			     (when
				 branches
			       (concat "@" (mapconcat 'identity branches " ")))))
	       (txtid (concat filter (car (split-string (car location) "_"))))
	       (line (car (cdr (cdr location))))
	       (pag (car (cdr location)) ) 
	       (page (if (string-match "[-_]"  pag)
			 (concat (substring pag 0 (- (length pag) 1))
				 (mandoku-num-to-section (substring pag (- (length pag) 1))) line)
		       (concat
			pag
			line)))
	       (vol (mandoku-textid-to-vol txtid))
	       (dummy "○")
	       (tit (concat "《" (mandoku-textid-to-title txtid) "》")))
	  (push (cons (format "%s %-10.10s %s%s %s" txtid
			      (concat (if vol
				  (concat vol ", ")
				(or (ignore-errors (concat (number-to-string (string-to-number (cadr (split-string (car location) "_")))) ","))
				    ""))
			      (replace-regexp-in-string "^0+" "" page))
			      
			      (replace-regexp-in-string "[\t\s\n+]" "" pre)
			      (replace-regexp-in-string "\\\[\\\[file:\\([^]]*\\)\\\]\\\]" 'mandoku-rep-img-in-string 
		 	(mandoku-hi-in-string (replace-regexp-in-string "[\t\s\n+]" "" post) search-string))
			(propertize dummy 'display tit))
		      (format "%s:%s::%s"  txtf page search-string)) l))))
    (nreverse l)
    ))

(defvar mandoku-index-helm-source
	 '((name . "Mandoku Index")
	   ;(fuzzy-match . t)
	   (candidates . mandoku-helm-index-candidates)
	   (action . (("Open" . (lambda (candidate)
				  (mandoku-link-open candidate)))))))
  
(defun mandoku-index-helm()
  (interactive)
  (helm :sources '(mandoku-index-helm-source)))

(defun mandoku-index-sort-func (type s)
  (when (derived-mode-p 'mandoku-index-mode)
    (goto-char (point-min))
    (org-next-visible-heading 1)
    (org-sort-entries t type nil nil s)
    (mandoku-refresh-images)
    (hide-sublevels 2)))

(defun mandoku-index-sort-pre ()
  "sort the result index by the preceding string, this has been saved in the property PRE"
  (interactive)
  (mandoku-index-sort-func ?r "PRE")
  (message "Sorted the index with the characters preceding the match as sort key."))

(defun mandoku-index-sort-post ()
  "sort the result index by the following string, this has been saved in the property POST"
  (interactive)
  (mandoku-index-sort-func ?r "POST")
  (message "Sorted the index with the characters following the match as sort key."))

(defun mandoku-index-sort-id ()
  "sort the result index by the text number, this has been saved in the property ID"
  (interactive)
  (mandoku-index-sort-func ?r "ID")
  (message "Sorted the index with the text number as sort key."))

(defun mandoku-index-sort-textdate ()
  "sort the result index by the text date, this has been saved in the property TXTDATE"
  (interactive)
  (mandoku-index-sort-func ?r "TXTDATE")
  (message "Sorted the index with the text date as sort key."))

(defun mandoku-index-sort-hits ()
  "sort the result index by the number of hits that been saved in the property HITS"
  (interactive)
  (mandoku-index-sort-func ?R "HITS")
  (message "Sorted the index with the number of hits as sort key."))

(defun mandoku-index-toggle-variant-matches ()
  "Redisplay the *Mandoku Index* with the inverse setting for
variant matches."
  (interactive)  
  (let (
	(index-buffer (get-buffer "*temp-mandoku*"))
	(result-buffer (current-buffer))
	(search-string mandoku-search-for))
    (set-buffer result-buffer)
    (setq buffer-read-only nil)
    (erase-buffer)
    (setq mandoku-index-all-editions (not mandoku-index-all-editions))
    (mandoku-read-index-buffer index-buffer result-buffer search-string)
  (message "Redisplayed the index with the variant count as sort key.")))


(defun mandoku-index-sort-ncnt ()
  "sort the result index by the ngram count, this has been saved in the property NCNT"
  (interactive)
  (mandoku-index-sort-func ?R "NCNT")
  (message "Sorted the index with the ngram count as sort key."))



(defun mandoku-closest-elm-in-seq (n seq)
  "returns the closest element which is larger or equal to n in sequence seq "
   (let ((pair (loop with elm = n with last-elm
                  for i in seq
                  if (eq i elm) return (list i)
                  else if (and last-elm (< last-elm elm) (> i elm)) return (list last-elm i)
                  do (setq last-elm i))))
     (if (> (length pair) 1)
         (if (< (- n (car pair)) (- (cadr pair) n))
             (car pair) (cadr pair))
         (car pair))))


(defun mandoku-format-on-punc ( rep)
  "Formats the text from point to the end, splitting at punctuation and other splitting points."
;  (interactive "s")
  (let ((curpos (point)))
    (while (search-forward "¶
" nil t )
      (replace-match "¶"))
    (goto-char curpos)
  ;; first, lets handle the line-endings
  (save-match-data
    (while (re-search-forward mandoku-punct-regex-post nil t)
      (if (or (looking-at "¶?[
]") (org-at-heading-p) (org-at-comment-p))
	  nil
	(replace-match (concat (match-string 1)  (match-string 2) rep)))
      (if (looking-at "¶?[	]")
	  (forward-line 1)
	(forward-char 1))
      )))
)

(defun mandoku-pre-format-on-punc (rep)
  "hallo"
  (save-match-data
    (while (re-search-forward mandoku-punct-regex-pre nil t)
      (if (or (org-at-heading-p) (org-at-comment-p))
	  nil
	(replace-match (concat (match-string 1) rep (match-string 2)))
	(forward-char 1)
	))))

(defun mandoku-format-with-p ()
  "Formats the whole file, adding the line marker to the end of the line"
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (looking-at "#")
      (forward-line 1))
    (mandoku-format-on-punc "¶
")
    (goto-char (point-min))
    (while (looking-at "#")
      (forward-line 1))
    (mandoku-pre-format-on-punc "¶
")))

(defun mandoku-format ()
  "Formats the whole file"
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (looking-at "#")
      (forward-line 1))
    (mandoku-format-on-punc "
")
    (goto-char (point-min))
    (while (looking-at "#")
      (forward-line 1))
    (mandoku-pre-format-on-punc "
")
))

(defun mandoku-format-add-p-numbers ()
  "For texts without page numbers, add paragraph numbers as a substitute"
  (interactive)
  (save-excursion
    (let ((cnt 0)
	  ;; this assumes a naming convention txtid_<nnn>.txt
	  (txtfn (split-string (car (split-string (file-name-nondirectory (buffer-file-name)) "\\.")) "_"))
	  (be (mandoku-get-baseedition)))
;    (goto-char (point-min))
    (forward-paragraph 1)
    (while (not (eobp))
      (setq cnt (+ cnt 1))
      (insert (concat "<pb:" (car txtfn) "_" be "_" (cadr txtfn) "-" (int-to-string cnt) "a>
"))
      (forward-paragraph 1)))))


(defun mandoku-string-remove-all-properties (string)
;  (set-text-properties 0 (length string) nil string))
  (condition-case ()
      (let ((s string))
	(set-text-properties 0 (length s) nil s) s)
    (error string)))


(defun mandoku-get-baseedition ()
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward ": BASEEDITION \\(.*\\)" (point-max) t)
      (mandoku-string-remove-all-properties (match-string 1)))))



(defun mandoku-get-title ()
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^#\\+TITLE: \\(.*\\)" (point-max) t)
      (car (last (split-string (mandoku-string-remove-all-properties  (match-string 1)) " ")))  )))
      
;;the mode for mandoku-index
(defvar mandoku-index-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "e" 'view-mode)
    ;(define-key map " " 'view-scroll-page-forward)
    (define-key map "t" 'manoku-index-no-filter)
    (define-key map "p" 'mandoku-index-sort-pre)
    (define-key map "d" 'mandoku-index-sort-textdate)
    (define-key map "f" 'mandoku-index-sort-post)
    (define-key map "i" 'mandoku-index-sort-id)
    (define-key map "h" 'mandoku-index-sort-hits)
    (define-key map "n" 'mandoku-index-sort-ncnt)
    (define-key map "v" 'mandoku-index-toggle-variant-matches)
         map)
  "Keymap for mandoku-index mode"
)

(define-derived-mode mandoku-index-mode org-mode "mandoku-index-mode"
  "a mode to view Mandoku index search results
  \\{mandoku-index-mode-map}"
  (setq case-fold-search nil)
  (set-variable 'tab-with 24 t)
;  (set (make-local-variable 'tab-with) 24)
  (set (make-local-variable 'org-startup-folded) "nofold")
  (mandoku-display-inline-images)
					;  (toggle-read-only 1)
;  (view-mode)
)


(defun mandoku-get-juan ()
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^#\\+PROPERTY: JUAN \\(.*\\)" (point-max) t)
      (mandoku-string-remove-all-properties (match-string 1)))))

(defun mandoku-get-vol ()
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^#\\+PROPERTY: VOL \\(.*\\)" (point-max) t)
      (mandoku-string-remove-all-properties (match-string 1)))))


(defun mandoku-page-at-point ()
  (interactive)
  (save-excursion
    (let ((p (point)))
      (re-search-backward "<pb:" nil t)
      (re-search-forward "\\([^_]*\\)_\\([^_]*\\)>" nil t)
      (setq textid (match-string 1))
      (setq page (match-string 2))
      (setq line 0)
      (while (and
	      (< (point) p )
	      (re-search-forward "¶" (point-max) t))
	(setq line (+ line 1)))
      (format "%s%2.2d" page line))))


(defun mandoku-get-subtree ()
  (interactive)
  (org-copy-subtree) 
  (kill-append (concat "\n(巻" (mandoku-get-juan) ", " (mandoku-get-heading) ", p" (mandoku-page-at-point) ")") nil ) ) 

(defun mandoku-get-line (&optional left)
  (car (split-string
	(buffer-substring-no-properties
	 (point-at-bol)
	 (point-at-eol)) "	")))

;; (easy-menu-define mandoku-md-menu org-mode-map "Mandoku menu"
;;   '("BK-MDA"
;;     ["Test" (lambda () (interactive) (insert "test!")) t]
;;     ))
  
(easy-menu-define mandoku-md-menu mandoku-view-mode-map "Mandoku menu"
  '("Mandoku"
    ("Browse"
     ["Show catalog" mandoku-show-catalog t]
     ["Update local catalog" mandoku-write-local-text-list t]
     )
    ("Display"
     ["Show markers" mandoku-toggle-visibility t])
    ("Search"
     ["Texts" mandoku-search-text t]
     ["Titles" mandoku-search-titles t]
;     ["Dictionary" mandoku-dict-mlookup t]
     ["My Files" mandoku-search-user-text t]
     )
    ("Editions"
     ["View this location in other edition" mandoku-location-other-branch t]
     )
    ("Maintenance"
     ["Reload title table" mandoku-read-titletables t]
     ["Download this text now!" mandoku-get-remote-text (string-match "fatal" (car (mandoku-get-branches)))]
     ["Download this text from other account" mandoku-get-remote-text-from-account (string-match "fatal" (car (mandoku-get-branches)))]
     ["Download my texts from GitHub" mandoku-get-user-repos-from-gh t]
;     ["Download texts in DL list" mandoku-download-process-queue t]
;     ["Add to download list" mandoku-download-add-text-to-queue t]
;     ["Show download list" mandoku-download-show-queue t]
     ["Commit, push and pull all texts" mandoku-update-texts t]
     ["Update search index" mandoku-update-index t]
     ["Setup file" mandoku-show-local-init t]
     ["Convert my work files" mandoku-find-files-to-convert t]
     ["Update mandoku" mandoku-update t]
;     ["Update installed texts" mandoku-update-texts nil]
     
;     ["Add repository" mandoku-gitlab-create-project (not (member mandoku-gitlab-remote-name (mandoku-get-remotes)))]
     )
))     

;; disabled this [2015-06-18T11:50:07+0900]
(defun mandoku-install-version-files-menu ()
  (let ((bl (buffer-list)))
    (save-excursion
      (while bl
	(set-buffer (pop bl))
	(if (derived-mode-p 'mandoku-view-mode) (setq bl nil)))
      (when (derived-mode-p 'mandoku-view-mode)
	(easy-menu-change
	 '("Mandoku") "Versions"
	 (append
	  (list
;	   ["Master" mandoku-switch-to-master nil]
	   ["New version" mandoku-new-version t]
	   "--")
	  (mapcar 'mandoku-version-menu-entry (mandoku-get-branches))))))))	  


(defun mandoku-version-menu-entry (branch)
  (vector branch (list 'mandoku-switch-version branch) t))
;; tab

(defun mandoku-index-tab-change (state)
  (interactive)
  (cond 
   ((and (eq major-mode 'mandoku-index-mode)
	     (memq state '(children subtree)))
    (save-excursion
      (let ((hw 	(car (split-string  (org-get-heading)))))
	(forward-line)
	(if (looking-at "\n")
	    (mandoku-index-insert-result (mandoku-index-get-search-string) "*temp-mandoku*" (current-buffer) hw))
	(mandoku-refresh-images)
	))
    )
   ))

(add-hook 'org-cycle-hook 'mandoku-index-tab-change) 

(defun mandoku-remove-nil-recursively (x)
  (if (listp x)
    (mapcar #'mandoku-remove-nil-recursively
            (remove nil x))
    x))

;;;###autoload
(defun mandoku-search-titles(key)
  "Show the matches of 'key' in the list of texts"
  (interactive "sMandoku | Search for title containing: ")
  (let ((myList (mandoku-hash-to-list mandoku-titles))
	(buf (get-buffer-create "*Mandoku Titles*"))
	(cnt 0))
    (set-buffer buf)
    (erase-buffer)
    (insert
       "Titles matching " key ": \n")
    (ignore-errors
    (dolist (x   
	     (sort myList (lambda (a b) (string< (car a) (car b)))))
      (if (and (< 4 (length (car x)))
	       (string-match  key (cadr x)))
	  (progn
	    (insert (format (concat "[[mandoku:"
				    "%s][%s %s]] \t\n") (car x) (car x)  (cadr x)))
	    (setq cnt (+ cnt 1))
	))))
    (org-mode)
    (goto-char (point-min))
    (end-of-line)
    (insert (format "(%d)" cnt))
    (next-line 1)
    (beginning-of-line)
    (display-buffer buf )
    ))
  

;; maintenance



(defun mandoku-update-index ()
  "Updates the index for local files"
  (interactive)
  (set-process-sentinel (start-process-shell-command "*index*" nil
			       (concat mandoku-python-program " " mandoku-sys-dir "python/updateindex.py " mandoku-base-dir)) 'mandoku-index-sentinel)
  (message "Started indexing.")
  )

(defun mandoku-index-sentinel (proc msg)
;  (if (string-match "finished" msg))
  (mandoku-read-indexed-texts) 
  (message "Index %s %s" proc msg)
  )

(defun mandoku-update()
  (interactive)
  (package-refresh-contents)
  (package-install (car (cdr (assoc 'mandoku package-archive-contents)))))

(defun mandoku-display-subcoll (key)
  "Show the matches of 'key.$' (that is, key and the next char) for a textid in the list of texts"
  (let ((myList (mandoku-hash-to-list (if (> (length key) 3) mandoku-titles
				      mandoku-subcolls)))
	(buf (get-buffer-create "*Mandoku Titles*")))
    (set-buffer buf)
    (erase-buffer)
    (insert
     (if (< 2 (length key)) (concat "([[mandoku:*:" (substring key 0 -1)  "][Up]]) " ) "")
       "Catalog entries for " key ": \n")
    (ignore-errors
    (dolist (x   
	     (sort myList (lambda (a b) (string< (car a) (car b)))))
      (if (string-match (concat key (if (> (length key) 3) ".+" ".$")) (car x))
	  (insert (format (concat "[[mandoku:"
			  (if (> (length key) 3) "" "*:")
			  "%s][%s %s]] \t\n") (car x) (car x)  (car (cdr x))))
	)))
    (org-mode)
    (goto-char (point-min))
    (next-line 1)
    (beginning-of-line)
    (display-buffer buf )
    ))

;; citfind

(defun mandoku-citfind (beg end)
  (interactive "r")
  (let ((tempfile (make-temp-file "citfind"))
	(citfind-buffer (get-buffer-create "*Mandoku-result*"))
	(default-directory mandoku-sys-dir)
	;(mandoku-python-program "/home/chris/.pyenv/shims/python")
	(src-txt  (car (last (split-string (buffer-file-name ) "/")))))
    (with-temp-file tempfile
      (insert (format "# %s\n" src-txt)))
    (write-region beg end tempfile t)
    (with-current-buffer citfind-buffer
      (shell-command (concat mandoku-python-program " " mandoku-sys-dir "/citfind.py " tempfile) citfind-buffer) 
    ;; mode
    (mandoku-index-mode)
    )))
			
;; convenience: abort when using mouse in other buffer
;; recommended by yasuoka-san 2013-10-22
(defun mandoku-abort-minibuffer ()
  "kill the minibuffer"
  (when (and (>= (recursion-depth) 1) (active-minibuffer-window))
    (abort-recursive-edit)))

(add-hook 'mouse-leave-buffer-hook 'mandoku-abort-minibuffer)

;; proxy on windows
(if (eq system-type 'windows-nt)
(eval-after-load "url"
  '(progn
     (require 'w32-registry)
     (defadvice url-retrieve (before
                              w32-set-proxy-dynamically
                              activate)
       "Before retrieving a URL, query the IE Proxy settings, and use them."
       (let ((proxy (w32reg-get-ie-proxy-config)))
         (setq url-using-proxy proxy
               url-proxy-services proxy))))))


(defun mandoku-shell-command (command param)
  (let ((ex       (or (executable-find command)
			(error (concat "Unable to find " command))))
	(default-directory (file-name-directory (buffer-file-name ))))
  (shell-command (concat ex param) " *mandoku-shell*")))

(defun mandoku-switch-version (branch)
;  (gd-shell-command (format "git checkout %s" branch)))
  (mandoku-shell-command mandoku-git-program (format " checkout %s" branch)))

(defun mandoku-new-version (&optional branch)
  (interactive)
  (setq branch (or branch (read-string "Create and switch to new branch: ")))
  (mandoku-shell-command mandoku-git-program (format " checkout -b %s" branch)))

(defun mandoku-get-remotes ()
  (let* ( (default-directory (file-name-directory (buffer-file-name )))
	  (res (shell-command-to-string (concat mandoku-git-program " remote"))) )
    (split-string res "\n")))
(defsubst mandoku-trim-and-star (s)
  "Remove whitespace and start at the beginning and the end of string S."
  (replace-regexp-in-string
   "\\`[ \t\n\r\*]+" ""
   (replace-regexp-in-string "[ \t\n\r]+\\'" "" s)))

  
(defun mandoku-get-branches ()
  (let* ( (default-directory (file-name-directory (buffer-file-name )))
	  (res (shell-command-to-string (concat mandoku-git-program " branch"))) )
    (delete "" (mapcar 'mandoku-trim-and-star (split-string res "\n")))))

(defun mandoku-get-current-branch ()
    (with-temp-buffer 
      (if (not (zerop (call-process mandoku-git-program nil t nil 
				   "--no-pager"  "symbolic-ref" "-q" "HEAD")))
	  "edition not known"
	(progn
; TODO: better solution for non-git files
;        (error "git error: %s " (buffer-string))
	  (goto-char (point-min))
	  (if (looking-at "^refs/heads/")
	      (buffer-substring 12 (1- (point-max)))))))
    )



;; routines to work with settings when loading settings.org
;;[2014-01-07T11:21:05+0900]

(defun mandoku-lc-car (row)
"Lowercases the first element in a list"
(list (downcase (car row)) (car (cdr row))))

(defun mandoku-set-settings  (uval)
  (let ((lcval (mapcar #'mandoku-lc-car  uval)))
    (setq mandoku-user-email (car (cdr (assoc "email" lcval ))))
    (setq mandoku-user-account (car (cdr (assoc "account" lcval ))))
    (setq mandoku-user-token (car (cdr (assoc "token" lcval ))))
    (setq mandoku-gh-server (car (cdr (assoc "server" lcval ))))
    (if (car (cdr (assoc "basedir" lcval )))
	(progn
	  (setq mandoku-base-dir  (expand-file-name (car (cdr (assoc "basedir" lcval )))))
	  (unless (eq "/" (substring mandoku-base-dir (- (length mandoku-base-dir) 1 )))
	    (setq mandoku-base-dir (concat mandoku-base-dir "/"))))
    )
))
;; need to expand this to check the cfg file if user not yet in mandoku-settings.org
(defun mandoku-get-user ()
  "Get the user.  Only if no user is set do we use the default."
  (or (if (< 0 (length mandoku-user-account))
	  mandoku-user-account)
      mandoku-gh-user))


(defun mandoku-get-password ()
  (or mandoku-user-password
      (setq mandoku-user-password
	    (read-passwd "Please enter your GitLab password: "))))



(defun mandoku-set-repos (uval)
  (setq mandoku-repositories-alist uval))


;; misc helper functions
;;;###autoload
(defun mandoku-write-local-text-list ()
  (interactive)
  (let ((textlist (sort (mandoku-list-local-texts) 'string<)))
    (with-current-buffer (find-file-noselect mandoku-local-catalog t)
      (erase-buffer)
    (insert "# -*- mode: mandoku-view; -*-
#+DATE: " (format-time-string "%Y-%m-%d\n" (current-time))  
"#+TITLE: 漢籍リスト

# このファイルは自動作成しますので、編集しないでください
# This file is generated automatically, so please do not edit

リンクをクリックするかカーソルをリンクの上に移動して<enter>してください
Click on a link or move the cursor to the link and then press enter

* Downloaded texts 個人漢籍
")
    (dolist (x textlist)
      (insert 
       (if (> (length x) 3)
	   "**"
	 "*")
       (format " [[mandoku:%s][%s %s]]\n" x x
	       (gethash x  mandoku-titles))))
    (save-buffer)
    (mandoku-view-mode)
    (show-all)
    (goto-char (point-min))
  )))

(defun mandoku-list-local-texts (&optional directory)
  "List local texts by textid. "
  (interactive)
  (let (el-files-list
        (current-directory-list
         (directory-files-and-attributes (or directory mandoku-text-dir) t)))
    ;; while we are in the current directory
    (while current-directory-list
      (cond
       ;; check to see whether filename ends in `.git'
       ;; and if so, append its name to a list.
       ((equal ".git" (substring (car (car current-directory-list)) -4))
        (setq el-files-list
              (cons (car (car current-directory-list)) el-files-list)))
       ;; check whether filename is that of a directory
       ((eq t (car (cdr (car current-directory-list))))
        ;; decide whether to skip or recurse
        (unless (or 
            ;; then do nothing since filename is that of
            ;;   current directory or parent, "." or ".."
	     (equal "."
		    (substring (car (car current-directory-list)) -1))
	     (equal "_data"
		    (substring (car (car current-directory-list)) -5))
	     (equal "_branches"
	          (substring (car (car current-directory-list)) -9)))
          ;; else descend into the directory and repeat the process
          (setq el-files-list
                (append
		 (mandoku-list-local-texts
                  (car (car current-directory-list)))
                 el-files-list)))))
      ;; move to the next filename in the list; this also
      ;; shortens the list so the while loop eventually comes to an end
      (setq current-directory-list (cdr current-directory-list)))
    ;; return the filenames
    (mapcar 'mandoku-get-textid-from-filename el-files-list)))

(defun mandoku-get-textid-from-filename (fn)
  "fn is the filename including .git extension as in the mandoku-text-dir"
  (let ((fnlist (split-string fn "/")))
  (nth (- (length fnlist ) 2 )  fnlist))
  )

(defun mandoku-textid-to-filename (textid)
  "Calculates the full path to a text from the text id."
  (concat mandoku-text-dir (substring textid 0 4) "/" textid))

(defun mandoku-start ()
  "return the start of region if a region is active, otherwise point"
  (if (org-region-active-p)
      (region-beginning)
    (point)))

(defun mandoku-text-local-p (txtid)
  "check if the text has been cloned and is available locally"
    (file-exists-p (concat mandoku-text-dir (mandoku-subcoll txtid ) "/" txtid)))

(defun mandoku-subcoll (txtid)
  (mapconcat 'identity (butlast (split-string (replace-regexp-in-string "\\([0-9][A-z]+\\)" " \\1 " txtid ))) ""))

(defun mandoku-get-textid ()
  "looks for a textid close to the cursor"
  (let ((fn (car (split-string (file-name-sans-extension (file-name-nondirectory (buffer-file-name ))) "_")))
      (begol (point-at-bol))
      (endol (point-at-eol))
      (wap (or (word-at-point) "")))
    (if (string-match mandoku-textid-regex fn)
	fn
      (if (string-match mandoku-textid-regex wap)
	  wap
	(save-excursion
	  (goto-char begol)
	  (if (re-search-forward (concat "\\(" mandoku-textid-regex "\\)") endol t 1)
	      (buffer-substring-no-properties (match-beginning 1) (match-end 1))))
	))))


(defun mandoku-split-textid (txtid)
  "split a text id in repository id, subcoll and sequential number of the text"
  (split-string (replace-regexp-in-string "\\([0-9][A-z]+\\)" " \\1 " txtid )))

(defun mandoku-remove-markup (str)
  "removes the special characters used by mandoku from the string"
  (replace-regexp-in-string "\\(?:<[^>]*>\\)?¶?" ""
    (replace-regexp-in-string "\\(\t.*\\)?\n" "" str)))

(defun mandoku-remove-punct-and-markup (str)
  (comment-string-strip
   (replace-regexp-in-string "\\([　-㏿！-￮]\\)" ""
                             (mandoku-remove-markup str))
   t t ))

(defun mandoku-split-string (str)
  "Given a string of the form \"str1::str2\", return a list of
  two substrings \'(\"str1\" \"str2\"). If no ::, then return empty string. If there are several ::, signal error."
  (let ((strlist (split-string str "::")))
    (cond ((= 1 (length strlist))
           (list (car strlist) ""))
          ((= 2 (length strlist))
           strlist)
          (t (error "mandoku-split-string: only one :: allowed: %s" str)))))

;; don't really understand this, so not removing for now...
;; (defun mandoku-chomp (str)
;;   "Chomp leading and tailing whitespace from STR."
;;   (replace-regexp-in-string (rx (or (: bos (* (any " \t\n")))
;; 				    (: (* (any " \t\n")) eos)))
;; 			    ""
;; 			    str))

(defun mandoku-refresh-images ()
  "Refreshes images displayed inline."
  (interactive)
  (org-remove-inline-images)
  (org-display-inline-images))

(defun mandoku-get-extra (rep)
  (condition-case nil
      ;; first try the user
      (mandoku-clone-repo (concat  (github-clone-user-name) "/" rep) (concat mandoku-base-dir rep) )
    (error 
    (mandoku-clone-repo (concat  "kanripo/" rep) (concat mandoku-base-dir rep) )
    )))

(defun mandoku-add-to-for-commit-list ()
  (ignore-errors
  (let ((fn (magit-toplevel (buffer-file-name (current-buffer)))))
  (if (string-match mandoku-text-dir fn)
      (add-to-list 'mandoku-for-commit-list fn )))))

(defun mandoku-commit-from-list ()
  (interactive)
  (dolist (x mandoku-for-commit-list)

    ))

(defun mandoku-git-config-get (section item)
  (let ((default-directory (expand-file-name "~/")))
    (ignore-errors (substring
     (shell-command-to-string (concat mandoku-git-program " config --global --get " section "." item  )) 0 -1))))

(defun mandoku-git-config-set (section item value)
  (let ((default-directory (expand-file-name "~/")))
     (shell-command-to-string (concat mandoku-git-program " config --global " section "." item " " value  ))))

(defun mandoku-git-prepare-info()
  "Make sure we have name and email so that we can commit"
  (unless (mandoku-git-config-get "user" "name")
    (mandoku-git-config-set "user" "name"
   (read-string "Git needs a name to identify you. How should git call you? " (or (user-full-name)  (user-login-name)))))
  (unless (mandoku-git-config-get "user" "email")
    (mandoku-git-config-set "user" "email"
    (read-string "Git needs an email alias to identify you. How should git mail you? "
		 (concat (or
			  (replace-in-string (user-login-name) " " "")
			  (replace-in-string (user-full-name) " " ""))
    "@" (system-name))))))
  
(defcustom update-texts-sh "#!/bin/sh
# version #0.01#
# automate committing and fetching.  This is called from the mandoku command
cd \"$(dirname ${0%/*})/text\"
cwd=`pwd`
remote=$1
#this script needs to be run in the $krp/text directory
for d in */*
do
    echo $d
    if [ -d $d ]
    then
	cd $d
	# fetch from remote
	for branch in `git branch -a | grep -v remotes | grep -v HEAD | sed -e 's/* \(.*\)/\1/'`; do
	    git fetch $remote $branch
	done
	# Remove deleted files
	git ls-files --deleted -z | xargs -0 git rm >/dev/null 2>&1
	# Add new files
	git add . >/dev/null 2>&1
	git commit -am \"$(date)\"
	for branch in `git branch -a | grep -v remotes | grep -v HEAD | sed -e 's/* \(.*\)/\1/'`; do
	    git push $remote $branch
	done
	cd $cwd
    fi
done
"
  "Script to update the text repositories. Part of mandoku to make updating easier."
  :type '(string)
  :group 'mandoku-system)

;; this will activate the automatic saving, commit and push:
;; (run-at-time "00:59" 1800 'mandoku-update-texts)
(defun mandoku-update-texts ()
  (interactive)
  ;; first, save the relevant buffers.
  (save-some-buffers t (lambda () (derived-mode-p 'mandoku-view-mode)))
  ;; in the future propably will need to check for the version of this file...
  (unless (file-exists-p (concat mandoku-sys-dir "gitupd.sh"))
    (with-current-buffer (find-file-noselect (concat mandoku-sys-dir "gitupd.sh") t)
      (insert update-texts-sh)
      (save-buffer)
      (kill-buffer)))
  (start-process-shell-command
   " *gitupd*"
   " *gitupd-buffer*"
   (concat "sh "  mandoku-text-dir "gitupd.sh "
	   (mandoku-git-config-get "github" "user")))  
)

;; dealing with branches
(defun mandoku-get-active-branches (cd)
  ;; active are the branches currently under "_branches"
					;  (prune-directory-list (directory-files  (concat (file-name-directory (buffer-file-name)) "_branches") t "^[^\.]+"  ))
    (if (file-exists-p cd)
	(directory-files cd nil "^[^\.]+"  )
      nil
      ))
  
(defun mandoku-location-other-branch (&optional branch)
  (interactive)
  (let* ((cd (concat (file-name-directory (buffer-file-name)) "_branches"))
	 (p (substring (cadr (split-string (mandoku-position-at-point) )) 1))
	(b (ido-completing-read "Edition: " (delete "_data" (mandoku-get-branches)) nil t))
	(bf (concat cd "/" b "/" (file-name-nondirectory buffer-file-name) )))
    (unless (file-exists-p bf)
      (mandoku-checkout-other-branch b))
    (when (file-exists-p bf)
      (find-file-other-window bf)
      (mandoku-execute-file-search p)
)))

(defun mandoku-checkout-data-branch ()
  (interactive)
  (mandoku-checkout-other-branch "_data")
  )

(defun mandoku-checkout-other-branch (&optional br)
  (interactive)
  (let* ((fn (file-name-directory (buffer-file-name)))
	 (cd (if (string= br "_data") fn (concat fn "_branches/")))
	 (branch (or br (ido-completing-read "Edition: " (delete "_data" (mandoku-get-branches))) nil t)
	 ))
    (unless (file-exists-p cd)
      (make-directory cd))
    (unless (file-exists-p (concat cd branch))
      (mandoku-shell-command mandoku-git-program (format " clone -b %s --single-branch %s %s/%s" branch fn cd branch)))))
;; file maintenance

(defun mandoku-remove-zhu-and-trans (textid)
  (mandoku-map-textid-files textid 'mandoku-remove-zhu)
  (mandoku-map-textid-files textid 'mandoku-remove-trans))

(defun mandoku-map-textid-files (textid func)
  (let ((tdir (concat mandoku-text-dir (substring textid 0 4) "/" textid)))
    (mapcar func (directory-files tdir t ".*txt$" ))))

(defun mandoku-remove-zhu (file)
  "This removes the zhu from the file"
  (with-current-buffer (find-file-noselect file)
    (fundamental-mode)
    (goto-char (point-min))
    (while (search-forward mandoku-annot-start nil t)
      (setq beg (match-beginning 0))
      (search-forward mandoku-annot-end)
      (setq end (match-end 0))
      (delete-region beg end))
    (save-buffer)
    (kill-buffer)))

(defun mandoku-remove-trans (file)
  "Remove translation (everything to the right of the tab) from
the file."
  (with-current-buffer (find-file-noselect file)
    (fundamental-mode)
    (goto-char (point-min))
    (while (re-search-forward "\t.*" nil t)
      (delete-region (match-beginning 0) (match-end 0)))
    (save-buffer)
    (kill-buffer)))


(defun mandoku-open-file-narrow (filename loc)
  "Open a file. Narrow to the area around the requested location.
This location can be a line-number or a mandoku-location, like 580a06:1::晉侯"
  (find-file-other-window filename)
  (fundamental-mode)
  (mandoku-execute-file-search loc)
)

(defun mandoku-rep-img-in-string (imgfile)
  "Replace the org-type image link with the image as property. To be used in `replace-regexp-in-string'"
  (let (img
	(file (match-string 1 imgfile))
	(dummy "○"))
    (when (file-exists-p file)
      (setq img (create-image file))
      (when img
	(propertize dummy 'display (cons 'image  img))))))
      
(defun mandoku-hi-in-string (str hi)
  "Highlight 'hi' in str."
  (let ((s (split-string str hi)))
    (mapconcat 'identity s (propertize hi 'face 'hi-yellow))))

;; git config --global credential.helper wincred
;; one more
;; and again.
(provide 'mandoku)

;;; mandoku.el ends here

