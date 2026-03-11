;;; du.el ---                                        -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Qiqi Jin

;; Author: Qiqi Jin <ginqi7@gmail.com>
;; Keywords:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:
(require 'ctable)
(require 'transient)

;;; Classes

(defclass du-cell ()
  ((value :initarg :value :reader du-cell-value)
   (header :initarg :header :reader du-cell-header))
  "Represents a single cell in the disk usage table.
Contains a parsed VALUE and its associated HEADER metadata.")

(defclass du-header ()
  ((title :initarg :title :reader du-header-title)
   (cmodel :initarg :cmodel :reader du-header-cmodel)
   (parser :initarg :parser :reader du-header-parser)
   (formatter :initarg :formatter :reader du-header-formatter)
   (sorter :initarg :sorter :reader du-header-sorter))
  "Represents a column header in the disk usage table.
Contains TITLE symbol, ctable CMODEL, PARSER function to convert raw strings,
FORMATTER function to display cell values, and SORTER function for comparison.")

;;; Custom Variables

(defcustom du-command "du -a -b --max-depth=1"
  "Shell command used to list disk usage.
The command is split and executed with the target directory appended.")

(defcustom du-headers
  (list (du-header :title 'size :cmodel (make-ctbl:cmodel :title "Size" :align 'right)
                   :parser (lambda (str) (string-to-number (car (split-string str "\t+"))))
                   :formatter (lambda (cell) (file-size-human-readable (du-cell-value cell) 'si))
                   :sorter (lambda (cell1 cell2) (< (du-cell-value cell1) (du-cell-value cell2))))
        (du-header :title 'path :cmodel (make-ctbl:cmodel :title "Path" :align 'left)
                   :parser (lambda (str) (nth 1 (split-string str "\t+")))
                   :formatter (lambda (cell) (format "%s" (du-cell-value cell))))
        (du-header :title 'type :cmodel (make-ctbl:cmodel :title "Type" :align 'left)
                   :parser (lambda (str) (if (file-directory-p (format "%s" (nth 1 (split-string str "\t+")))) "Dir" "File"))
                   :formatter (lambda (cell) (format "%s" (du-cell-value cell)))))
  "List of `du-header' objects defining table columns.
Each header specifies how to parse, format, and sort its column data.")

(defcustom du-output-parser #'du--output-default-parser
  "Function to parse raw `du' command output into structured data.
Takes the command output string and returns a list of cell rows.")

;;; Internal Variables

(defvar du--render-buffer-name "*du*"
  "Name of the buffer used to display the disk usage table.")

(defvar du--sort-col (nth 0 du-headers)
  "Current header used for sorting the table data.")

;;; Internal Functions

(defun du--cell (cell-str)
  "Extract the `du-cell' object from CELL-STR text property.
Parses a cell string from the ctable display and retrieves the stored
`du-cell' object from the `du-cell' text property."
  (with-temp-buffer
    (insert cell-str)
    (get-text-property (point-min) 'du-cell)))

(defun du--get-point-cell ()
  "Get the `du-cell' object at the current cursor position in the table.
Retrieves the selected cell from the ctable component and extracts
the underlying `du-cell' object from its text property."
  (let* ((cell (ctbl:cp-get-selected-data-cell (ctbl:cp-get-component)))
         (du-cell (with-temp-buffer
                    (insert cell)
                    (get-text-property (point-min) 'du-cell))))
    du-cell))

(defun du--output-default-parser (output)
  "Parse OUTPUT from `du' command into a list of cell rows.
Each line is split by tabs, and each part is parsed into a `du-cell' object
using the corresponding header's parser function."
  (let* ((lines (split-string output "\n" t))
         (result
          (mapcar (lambda (line)
                    (mapcar (lambda (header) (du-cell--build :header header :str line)) du-headers))
                  lines)))
    result))

(cl-defun du-cell--build (&key header str)
  "Build a `du-cell' object from HEADER and raw string STR.
Uses the header's parser function to convert STR into the cell value."
  (let* ((parser (du-header-parser header))
         (value (funcall parser str)))
    (du-cell :value value :header header)))

(defun du--to-ctable-data (du-data)
  "Convert DU-DATA into ctable display format.
Applies each cell's formatter function and adds text properties for interaction.
Sorts the data using the current `du--sort-col' sorter function."
  (mapcar
   (lambda (row)
     (mapcar
      (lambda (cell)
        (propertize (funcall (du-header-formatter (du-cell-header cell)) cell)
                    'du-cell cell))
      row))
   (sort du-data :key #'car :lessp (du-header-sorter du--sort-col))))

(defun du--sort-by-title (du-data)
  "Sort DU-DATA by the title column.
This is an unused helper function reserved for potential future sorting
by the path/title field.")

(defun du-ctable-show (du-data)
  "Display DU-DATA in a ctable buffer.
Creates a ctable model from the data and displays it in `du--render-buffer-name'.
Binds the `du-actions' transient menu to click events."
  (with-current-buffer (get-buffer-create (format "%s: %s"du--render-buffer-name default-directory))
    (let* ((column-model (mapcar #'du-header-cmodel du-headers))
           (data (du--to-ctable-data du-data))
           (model ; data model
            (make-ctbl:model
             :column-model column-model :data data))
           (component)
           (inhibit-read-only t))
      (erase-buffer)
      (setq component (ctbl:create-table-component-region :model model))
      (ctbl:cp-add-click-hook component #'du-actions))
    (setq buffer-read-only t)
    (switch-to-buffer (current-buffer))))

(defun du (&optional directory callback)
  "Run disk usage analysis on DIRECTORY and display results.
Interactively prompts for a directory. Runs `du-command' asynchronously
and passes the parsed results to CALLBACK (defaults to `du-ctable-show')."
  (interactive "Ddirectory: ")
  (when (and directory (file-directory-p directory))
    (setq default-directory (expand-file-name directory)))
  (let* ((dir default-directory)
         (buffer (generate-new-buffer " *du-output*")))
    (print (append (split-string du-command) (list dir)))
    (unless callback
      (setq callback #'du-ctable-show))
    (make-process
     :name "du"
     :buffer buffer
     :command (append (split-string du-command) (list dir))
     :noquery t
     :filter (lambda (proc string)
               (let ((old-point (point))
                     (inhibit-read-only t))
                 (with-current-buffer buffer
                   (goto-char (process-mark proc))
                   (insert string)
                   (set-marker (process-mark proc) (point))
                   (goto-char old-point)
                   (message "du ..."))))
     :sentinel (lambda (proc event)
                 (when t ;;(memq (process-status proc) '(exit signal))
                   (let* ((output (with-current-buffer (process-buffer proc)
                                    (buffer-string)))
                          (result (funcall du-output-parser output)))
                     (kill-buffer (process-buffer proc))
                     (if callback
                         (funcall callback result)
                       (message "du done."))))))))

(defun du-delete ()
  "Delete the file or directory at the selected table row.
Prompts for confirmation before deletion. If the path is a directory,
deletes it recursively; otherwise, deletes the file. Refreshes the
table view after successful deletion."
  (interactive)
  (let* ((cp (ctbl:cp-get-component))
         (row (ctbl:cp-get-selected-data-row cp))
         (cells (mapcar #'du--cell row))
         (path-cell (find-if (lambda (cell) (equal 'path (du-header-title (du-cell-header cell)))) cells))
         (path (du-cell-value path-cell)))
    (when (yes-or-no-p (format "Are you sure to delete [%s]" path))
      (if (f-directory-p path)
          (delete-directory path t)
        (delete-file path))
      (du))))

(defun du-enter ()
  "Navigate into the directory at the selected table row.
Retrieves the path from the selected row and invokes `du' recursively
on that directory to drill down into its contents."
  (interactive)
  (let* ((cp (ctbl:cp-get-component))
         (row (ctbl:cp-get-selected-data-row cp))
         (cells (mapcar #'du--cell row))
         (path-cell (find-if (lambda (cell) (equal 'path (du-header-title (du-cell-header cell)))) cells)))
    (du (du-cell-value path-cell))))

(defun du-sort ()
  "Prompt to select a column and sort the table by it.
Allows the user to choose which header column to use for sorting
the disk usage data. Updates `du--sort-col' and refreshes the view."
  (interactive))

(transient-define-prefix du-actions ()
  "Transient prefix menu for disk usage table actions.
Binds contextual actions to selected rows in the ctable display,
including delete, sort, and navigation commands."
  ["Disk Usage Actions"
   ("d" "Delete" du-delete)
   ("s" "Sort" du-sort)
   ("RET" "Enter" du-enter)])

(provide 'du)
;;; du.el ends here
