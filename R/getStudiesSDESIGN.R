################################################################################
## The function getStudiesSDESIGN.
##
## History:
## -----------------------------------------------------------------------------
## Date         Programmer            Note
## ----------   --------------------  ------------------------------------------
## 2020-12-04   Bo Larsen             Initial version
################################################################################

#' Extract a list of SEND studies with a specified study design.
#'
#' Returns a data table with the list of study ids from TS where the value of
#' TSVAL for the TSPARMCD 'SDESIGN' is equal to a given study design.\cr
#' If the \code{studyDesignFilter} is empty (null, na or empty string) - all
#' rows for the TSPARMCD 'SDESIGN' are returned.
#'
#' Extracts the set of studies from TS where the value of TSVAL for the TSPARMCD
#' 'SDESIGN' is equal to a given study design.\cr
#' The comparison of study design values are done case insensitive.\cr
#' If a data table with a list of studies is specified in \code{studyList}, only
#' the subset of studies included in that set is processed.
#'
#' If input parameter \code{inclUncertain=TRUE}, uncertain animals are included
#' in the output set. These uncertain situations are identified and reported (in
#' column UNCERTAIN_MSG):
#' \itemize{
#' \item without any row for TSPARMCD='SDESIGN' or
#' \item TSVAL doesn't contain a value included in the  CDISC CT list
#'      'DESIGN' for TSPARMCD='SDESIGN'
#' }
#' The same checks are performed and reported in column NOT_VALID_MSG if
#' \code{studyDesignFilter} is empty and \code{noFilterReportUncertain=TRUE}.
#'
#' @param dbToken Mandatory - token for the open database connection
#' @param studyList Optional.\cr
#'  A data.table with the list of studies to process. If empty, all studies in
#'  the data base are included processing \cr
#'  The table must include at least a column named 'STUDYID'
#' @param studyDesignFilter Mandatory, character. The study design to use as
#'   criterion for filtering of the study id values. It can be a single string,
#'   a vector or a list of multiple strings.
#' @param exclusively Optional.
#'   \itemize{
#'     \item TRUE: Include studies only for studies with no other study design
#'   then included in \code{studyDesignFilter}.
#'     \item FALSE: Include animals for all studies with study design matching
#'   \code{studyDesignFilter}.
#'   }
#' @param inclUncertain Optional, TRUE or FALSE, default: FALSE.\cr
#' Indicates whether study ids with SDESIGN value which are is missing or wrong
#' shall be included or not in the output data table.
#' @param noFilterReportUncertain  Optional, TRUE or FALSE, default: TRUE\cr
#'  Only relevant if the \code{studyDesignFilter} is empty.\cr
#'  Indicates if the reason should be included if the SDESIGN cannot be
#'  confidently decided for an animal.
#'
#' @return The function returns a data.table with columns:
#'   \itemize{
#'   \item STUDYID       (character)
#'   \item Additional columns contained in the \code{studyList} table (if such an input
#'   table is given)
#'   \item SDESIGN       (character)
#'   \item UNCERTAIN_MSG (character)\cr
#' Included when parameter \code{inclUncertain=TRUE}.\cr
#' Contains indication of whether STSTDTC is missing of has wrong
#' format.\cr
#' Is NA for rows where SDESIGN is valid.\cr
#' A non-empty UNCERTAIN_MSG value generated by this function is merged with
#' non-empty UNCERTAIN_MSG values which may exist in the optional input set of
#' studies specified in \code{studyList} - separated by '|'.
#'   \item NOT_VALID_MSG (character)\cr
#' Included when parameter \code{noFilterReportUncertain=TRUE}.\cr
#' In case the SDESIGN cannot be confidently decided, the column contains an
#' indication of the reason.\cr
#' Is NA for rows where SDESIGN can be confidently decided.\cr
#' A non-empty NOT_VALID_MSG value generated by this function is merged with
#' non-empty NOT_VALID_MSG values which may exist in the input set of studies
#' specified in \code{studyList} - separated by '|'.
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' GetStudyListSDESIGN(myDbToken, 'PARALLEL')
#' }


getStudiesSDESIGN <- function(dbToken,
                              studyList=NULL,
                              studyDesignFilter=NULL,
                              exclusively=TRUE,
                              inclUncertain=FALSE,
                              noFilterReportUncertain = TRUE) {

  if ((is.null(studyDesignFilter) | isTRUE(is.na(studyDesignFilter)) | isTRUE(studyDesignFilter=="")))
    execFilter <- FALSE
  else
    execFilter <- TRUE

  if (execFilter & !(inclUncertain %in% c(TRUE,FALSE))) {
    stop("Parameter inclUncertain must be either TRUE or FALSE")
  }
  if (!execFilter & !(noFilterReportUncertain %in% c(TRUE,FALSE))) {
    stop("Parameter noFilterReportUncertain must be either TRUE or FALSE")
  }

  studyListIncl<-FALSE
  if (data.table::is.data.table(studyList)) {
    # An initial list of studies is included
    studyListIncl<-TRUE
  }

  # Extract TS parameter 'SDESIGN'
  # - include a row for each for study which may miss a SDESIGN parameter
  tsSDESIGN <-
    genericQuery(dbToken, "select ts0.studyid,
                                  case
                                    when ts1.tsval = '' then null
                                    else ts1.tsval
                                  end as SDESIGN
                             from (select distinct STUDYID from ts) ts0
                             left join ts ts1
                               on ts0.studyid = ts1.studyid
                              and ts1.tsparmcd = 'SDESIGN'")

  if (studyListIncl) {
    # Limit to the set of studies given as input
    tsSDESIGN<-data.table::merge.data.table(tsSDESIGN, studyList[,list(STUDYID)], by='STUDYID')
  }

  # Check if a message column for uncertainties shall be included
  msgCol =''
  if (execFilter & inclUncertain)
    msgCol = 'UNCERTAIN_MSG'
  else {
    if (!execFilter & noFilterReportUncertain)
      msgCol = 'NOT_VALID_MSG'
  }

  if (msgCol != '') {
    # Check SDESIGN value for uncertainty for each extracted row.

    # Get values of codelist DESIGN from CDISC CT
    ctDESIGN<-getCTCodListValues(dbToken, "DESIGN")

    # Verify if SEX is within the SEX code list
    tsSDESIGN[, MSG :=  ifelse(! (toupper(SDESIGN) %in% ctDESIGN),
                               ifelse(is.na(SDESIGN),
                                     'SDESIGN: TS parameter SDESIGN is missing',
                                     'SDESIGN: TS parameter SDESIGN does not contain a valid CT value'),
                               as.character(NA))]
    # Rename MSG col to correct name
    data.table::setnames(tsSDESIGN, 'MSG' ,msgCol)
  }

  if (execFilter) {
    # Execute filtering

    # Add variable with count of distinct study designs specified per study
    tsSDESIGN[, `:=` (NUM_SDESIGN = .N), by = STUDYID]

    # Construct the statement to apply the specified design
    designFilter<-'toupper(SDESIGN) %in% toupper(trimws(studyDesignFilter))'
    if (exclusively) {
      designFilter<-paste(designFilter, ' & NUM_SDESIGN==1', sep='')
    }

    if (inclUncertain)
      # Include condition for inclusion of identified uncertain rows
      designFilter<-paste(paste("(", designFilter), ") | ! is.na(UNCERTAIN_MSG)")

    # Build the statement to extract studies fulfilling the condition(s) and execute
    foundStudies <- eval(parse(text=paste0('tsSDESIGN[',designFilter,']')))
    foundStudies[,NUM_SDESIGN := NULL]
  }
  else
     foundStudies <- tsSDESIGN

  if (studyListIncl) {
    # Merge the list of extracted studies with the input set of studies to keep
    # any additional columns from the input table
    foundStudies<-data.table::merge.data.table(studyList, foundStudies, by='STUDYID')

    # Do final preparation of set of found studies and return
    return(prepareFinalResults(foundStudies, names(studyList), c('SDESIGN')))
  }
  else
    # Initial list if extracted studies
    # Do final preparation of set of found studies and return
    return(prepareFinalResults(foundStudies, '', c('STUDYID', 'SDESIGN')))
}

################################################################################
# Avoid  'no visible binding for global variable' notes from check of package:
STUDYID <- NULL
NUM_SDESIGN <- SDESIGN <- NULL



