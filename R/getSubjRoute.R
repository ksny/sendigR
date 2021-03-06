################################################################################
## The function getSubjRoute.
##
## History:
## -----------------------------------------------------------------------------
## Date         Programmer            Note
## ----------   --------------------  ------------------------------------------
## 2021-01-06   Bo Larsen             Initial version
################################################################################


###################################################################################
# Script name   : filterStudyAnimalRoute.R
# Date Created  : 16-Jan-2020
# Programmer    : Bo Larsen
# --------------------------------------------------------------------------------
# Change log:
# Programmer/date     Description
# -----------------   ------------------------------------------------------------
# <init/dd-Mon-yyyy>  <description>
#
# -------------------------------------------------------------------------------
#
# Input         : - The TS, EX and POOLDEF domains - are imported from the pooled SEND data
#                   store if they don't exist in workspace.
#                 - A data table specified in the input parameter animalList:
#                   It contains the list of animals to filter for specified route value(s)
#                   - must contain these character variables:
#                       STUDYID
#                       USUBJID
#                     other variables may be included
#                 - The CDISC CT code list ROUTE imported from a CDISC CT file.
#
###################################################################################

#' Extract the set of animals of the specified route of administration - or just
#' add actual route of administration for each animal.
#'
#' Returns a data table with the set of animals included in the
#' \code{animalList} of the route of administration specified in the
#' \code{routeFilter}.\cr
#' If the \code{routeFilter} is empty (null, na or empty string) - all rows from
#' \code{animalList} are returned with the a ROUTE column added.
#'
#' The route of administration per animal are identified by a hierarchical
#' lookup in these domains
#' \itemize{
#'   \item EX - If a single not empty EXROUTE value is found for animal, this is
#'   included in the output.\cr
#'   \item TS - if a single TS parameter 'SPECIES' value exists for the study,
#'   this is included in the output.\cr
#' }
# The comparison of route values is done case insensitive.
#
#' If input parameter \code{inclUncertain=TRUE}, uncertain animals are included
#' in the output set. These uncertain situations are identified and reported (in
#' column UNCERTAIN_MSG):
#' \itemize{
#'   \item TS parameter ROUTE is missing for study and no EX rows contain a
#'   EXROUTE value for the animal
#'   \item The selected EXROUTE or TS parameter ROUTE value is invalid (not CT
#'   value - CDISC code list ROUTE)
#'   \item Multiple EXROUTE values have been found for the animal
#'   \item Multiple TS parameter ROUTE values are registered for study but no EX
#'   rows contain a EXROUTE value for the animal
#'   \item The found EXROUTE value for animal is not included in the TS
#'   parameter ROUTE value(s) registered for study
#' }
#' The same checks are performed and reported in column NOT_VALID_MSG if
#' \code{routeFilter} is empty and \code{noFilterReportUncertain=TRUE}.
#'
#' @param dbToken Mandatory - token for the open database connection
#' @param animalList  Mandatory.\cr
#'  A data.table with the list of animals to process.\cr
#'  The table must include at least columns named 'STUDYID' and 'USUBJID'.
#' @param routeFilter  Optional, character.\cr
#'  The rout of administration value(s) to use as criterion for filtering of the
#'  input data table.\cr
#'  It can be a single string, a vector or a list of multiple strings.
#' @param inclUncertain  Mandatory, TRUE or FALSE, default: FALSE.\cr
#'  Indicates whether animals for which the route cannot be confidently
#'  identified shall be included or not in the output data table.
#' @param exclusively Optional.
#'   \itemize{
#'   \item TRUE: Include animals only for studies with no other routes then
#'   included in \code{routeFilter}.
#'   \item FALSE: Include animals for all studies with route
#'   matching \code{routeFilter}.
#' }
#' @param matchAll Optional.
#'   \itemize{
#'   \item TRUE: Include animals only for studies with route(s) matching all
#'   values in \code{routeFilter}.
#'   \item FALSE: Include animals for all studies with route matching at least
#'   one value in \code{routeFilter}.
#' }
#' @param noFilterReportUncertain  Optional, TRUE or FALSE, default: TRUE\cr
#'  Only relevant if the \code{routeFilter} is empty.\cr
#'  Indicates if the reason should be included if the route cannot be
#'  confidently decided for an animal.
#'
#'
#' @return The function returns a data.table with columns:
#'   \itemize{
#'   \item STUDYID       (character)
#'   \item Additional columns contained in the \code{animalList} table
#'   \item ROUTE         (character)
#'   \item UNCERTAIN_MSG (character)\cr
#' Included when parameter \code{inclUncertain=TRUE}.\cr
#' In case the ROUTE cannot be confidently matched during the filtering of data,
#' the column contains an indication of the reason.\cr
#' Is NA for rows where ROUTE can be confidently matched.\cr
#' A non-empty UNCERTAIN_MSG value generated by this function is merged with
#' non-empty UNCERTAIN_MSG values which may exist in the input set of animals
#' specified in \code{animalList} - separated by '|'.
#'   \item NOT_VALID_MSG (character)\cr
#' Included when parameter \code{noFilterReportUncertain=TRUE}.\cr
#' In case the ROUTE cannot be confidently decided, the column contains an
#' indication of the reason.\cr
#' Is NA for rows where the ROUTE can be confidently decided.\cr
#' A non-empty NOT_VALID_MSG value generated by this function is merged with
#' non-empty NOT_VALID_MSG values which may exist in the input set of animals
#' \code{animalList} - separated by '|'.
#'}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Extract animals administered oral or oral gavage plus uncertain animals
#' getSubjRoute(dbToken, controlAnimals,
#'                 routeFilter = c('ORAL', 'ORAL GAVAGE')
#'                 inclUncertain = TRUE)
#' # Extract animals administered oral or oral gavage.
#' # Do only include studies which include but route values
#' getSubjRoute(dbToken, controlAnimals,
#'                 routeFilter = c('ORAL', 'ORAL GAVAGE')
#'                 matchAll = TRUE)
#' # Extract animals administered subcutaneous.
#' # Include only animals from studies which do not contain other route values
#' getSubjRoute(dbToken, controlAnimals,
#'                 routeFilter = 'subcutaneous',
#'                 exclusively = TRUE)
#' # No filtering, just add ROUTE - do not include messages when
#' # these values cannot be confidently found
#' getSubjRoute(dbToken, controlAnimals,
#'                 noFilterReportUncertain = FALSE)
#' }
#'
getSubjRoute <- function(dbToken,
                            animalList,
                            routeFilter = NULL,
                            inclUncertain = FALSE,
                            exclusively  = FALSE,
                            matchAll = FALSE,
                            noFilterReportUncertain = TRUE) {

  ##################################################################################################################
  # Function to identify uncertain animals
  identifyUncertainROUTE <- function(ROUTE, ALL_ROUTE_EX, ALL_ROUTE_TS) {


    msgArr<-c()
    if (is.na(ROUTE)) {
      if (length(ALL_ROUTE_EX) > 1)
        msgArr<-c(msgArr, 'Multiple values for EXROUTE found')
      else if (length(ALL_ROUTE_TS) > 1)
        msgArr<-c(msgArr, 'Multiple TS parameters ROUTE found and EX rows with EXROUTE values are missing')
      else
        msgArr<-c(msgArr, 'TS parameters ROUTE and EX rows with EXROUTE values are missing')
    }
    else {
      if (! ROUTE %in% ctROUTE) {
        if (!is.null(ALL_ROUTE_EX) & ! ALL_ROUTE_EX %in% ctROUTE)
          msgArr<-c(msgArr, 'EXROUTE does not contain a valid CT value')
        else if (!is.null(ALL_ROUTE_TS) & ! ALL_ROUTE_TS %in% ctROUTE)
          msgArr<-c(msgArr, 'TS parameter ROUTE does not contain a valid CT value')
      }
      if (! is.null(ALL_ROUTE_EX) &
          ! is.null(ALL_ROUTE_TS) &
          ! TRUE %in% (ALL_ROUTE_EX %in% ALL_ROUTE_TS))
        msgArr<-c(msgArr, 'Mismatch in values of TS parameter ROUTE and EXROUTE')
    }
    msg<-paste(msgArr, collapse = ' & ')
    return(ifelse(msg=="", as.character(NA), paste0('ROUTE: ', msg)))
  }
  ##################################################################################################################

  # Verify input parameter
  if (!data.table::is.data.table(animalList)) {
    stop('Input parameter animalList must have assigned a data table ')
  }
  if (is.null(routeFilter) | isTRUE(is.na(routeFilter)) | isTRUE(routeFilter==''))
    execFilter <- FALSE
  else
    execFilter <- TRUE
  if (execFilter & !(inclUncertain %in% c(TRUE,FALSE))) {
    stop("Parameter inclUncertain must be either TRUE or FALSE")
  }
  if (execFilter & !(exclusively %in% c(TRUE,FALSE))) {
    stop("Parameter Exclusively must be either TRUE or FALSE")
  }
  if (execFilter & !(matchAll %in% c(TRUE,FALSE))) {
    stop("Parameter matchAll must be either TRUE or FALSE")
  }
  if (!execFilter & !(noFilterReportUncertain %in% c(TRUE,FALSE))) {
    stop("Parameter noFilterReportUncertain must be either TRUE or FALSE")
  }

  # List of studyid values included in the input table of animals
  animalStudies<-unique(animalList[,c('STUDYID')])

  #check if POOLDEF exists and if EX contains POOLDEF
  if (dbExistsTable(dbToken, 'POOLDEF') && 'POOLID' %in% dbListFields(dbToken, 'EX'))
    # select part of pool level rows from EX
    sqlPartPool <- "union
                        select pooldef.STUDYID,
                               pooldef.USUBJID,
                               EXROUTE
                         from pooldef
                         join ex
                           on ex.studyid = pooldef.studyid
                          and ex.poolid = pooldef.poolid
                          and exroute is not null
                          and exroute != ''
                        where pooldef.studyid in (:1)"
  else
    sqlPartPool <- ""


  # Extract unique set or rows from EX for all animals studies
  # included in the input table of animals.
  # Do only include rows with a non-empty value of EXROUTE
  allAnimals <-
    genericQuery(dbToken, paste0(
                  "select distinct STUDYID,
                          USUBJID,
                          case exroute
                            when '' then null
                            else exroute
                          end as EXROUTE
                     from ex
                    where studyid in (:1)
                      and exroute is not null
                      and exroute != ''",
                    sqlPartPool),
                 animalStudies)

  # Add variables with
  # - number of distinct EXROUTE values per study
  # - concatenation of all EXROUTE per animal
  #  (for animals with one distinct EXROUTE value this is equal to EXROUTE)
  allAnimals[, `:=` (NUM_ROUTE_EX = .N), by = list(STUDYID,USUBJID)]
  allAnimals[,`:=`(ALL_ROUTE_EX = c(.SD)), by = list(STUDYID,USUBJID), .SDcols='EXROUTE']

  # Limit the set to the animals included in the input set of animal
  #  - do only keep the calculated columns from allAnimals
  allAnimals <-
    data.table::merge.data.table(allAnimals[,c('STUDYID',
                                               'USUBJID',
                                               'ALL_ROUTE_EX',
                                               'NUM_ROUTE_EX')],
                                 animalList[,c('STUDYID', 'USUBJID')],
                                 by = c('STUDYID', 'USUBJID'),
                                 all.y = TRUE)



  # Extract TS parm ROUTE parameter for all studies in the input list of animals
  studyRoutes <-
    genericQuery(dbToken,
                 "select distinct studyid,
                         tsval as ROUTE_TS
                    from ts
                   where tsparmcd = 'ROUTE'
                     and tsval is not null
                     and tsval != ''
                     and studyid in (:1)",
                 animalStudies)

  # Add variables with
  # - number of distinct routes per study
  # - concatenation of all ROUTE values per study
  #  (for studies with one ROUTE this is equal to ROUTE_TS)
  studyRoutes[, `:=` (NUM_ROUTE_TS = .N), by = STUDYID]
  studyRoutes[,`:=`(ALL_ROUTE_TS = c(.SD)), by = STUDYID, .SDcols='ROUTE_TS']

  # Add calculated columns to the list of animals
  #  - do only keep the calculated columns from studyRoute
  allAnimals <-
    data.table::merge.data.table(allAnimals,
                                 unique(studyRoutes[,c('STUDYID',
                                                       'ALL_ROUTE_TS',
                                                       'NUM_ROUTE_TS')],
                                        by='STUDYID'),
                                 by = 'STUDYID',
                                 all.x = TRUE)

  #  Add variables
  #    - ROUTE with the first non-empty single value from EX or TS
  allAnimals[,`:=` (ROUTE=ifelse(NUM_ROUTE_EX > 1,
                                 as.character(NA),
                                 ifelse(NUM_ROUTE_EX == 1,
                                        as.character(ALL_ROUTE_EX),
                                        ifelse(NUM_ROUTE_TS == 1,
                                               as.character(ALL_ROUTE_TS),
                                               as.character(NA)))))]


  # Check if a message column for uncertainties shall be included
  msgCol =''
  if (execFilter && inclUncertain)
    msgCol = 'UNCERTAIN_MSG'
  else if (!execFilter && noFilterReportUncertain)
    msgCol = 'NOT_VALID_MSG'

  if (msgCol != '') {
    # Check ROUTE value for uncertainty for each extracted row.

    # Get values of code list ROUTE from CDISC CT
    ctROUTE<-getCTCodListValues(dbToken, "ROUTE")

    # Identify uncertain animals - add variable UNCERTAIN_MSG
    allAnimals[,`:=` (MSG = mapply(identifyUncertainROUTE,
                                   ROUTE,
                                   ALL_ROUTE_EX,
                                   ALL_ROUTE_TS))]

    # Rename MSG col to correct name
    data.table::setnames(allAnimals, 'MSG' ,msgCol)
  }

  if (execFilter) {
    # Extract animals matching the routeFilter
    foundAnimals<-allAnimals[ROUTE %in% routeFilter,
                             c('STUDYID', 'USUBJID', 'ROUTE')]

    if (exclusively) {
      # Exclude all animals belonging to studies which have other ROUTEs than the requested
      foundAnimals<-
        # unique(allAnimals[,c('STUDYID','ROUTE')]) %>%
        # # Set of possible ROUTE values per study in the input set of animals:
        # data.table::merge.data.table(unique(foundAnimals[,c('STUDYID')]),
        #                              by='STUDYID') %>%
        # # Set of studies (included in the found set of animals with matching ROUTE values) with possible
        # # ROUTE values not included in the routeFilter:
        # data.table::fsetdiff(unique(foundAnimals[,c('STUDYID', 'ROUTE')])) %>%
        # unique() %>%
        # # Set of studies to keep:
        # data.table::fsetdiff(unique(foundAnimals[,c('STUDYID')]),.) %>%
        # # Keep all animals for the list og found studies
        # data.table::merge.data.table(foundAnimals, ., by='STUDYID')
        #
        data.table::merge.data.table(foundAnimals,
              # Set of studies to keep:
              data.table::fsetdiff(unique(foundAnimals[,c('STUDYID')]),
                       # Set of studies (included in the found set of animals with matching ROUTE values) with possible
                       # ROUTE values not included in the routeFilter:
                       unique(data.table::fsetdiff(data.table::merge.data.table(# Set of possible ROUTE values per study in the input set of animals:
                                                                                unique(allAnimals[,c('STUDYID','ROUTE')]),
                                                                                unique(foundAnimals[,c('STUDYID')]), by='STUDYID'),
                                                   unique(foundAnimals[,c('STUDYID', 'ROUTE')]))[,c('STUDYID')])),
              by='STUDYID')
    }

    if (matchAll & length(routeFilter) > 1) {
      # Exclude animals belonging to studies which do not match all requested ROUTE values
      foundAnimals<-
        data.table::merge.data.table(foundAnimals,
              # Studies with equal number of distinct number of ROUTE values as included in the requested set of ROUTEs
              unique(foundAnimals[,c('STUDYID','ROUTE')])[,list(NUM_ROUTE = .N), by = STUDYID][NUM_ROUTE == length(routeFilter),c('STUDYID')],
              by='STUDYID')
    }

    if (inclUncertain)
      # Add the uncertain animals
      foundAnimals<-data.table::rbindlist(list(foundAnimals,
                                   allAnimals[!is.na(UNCERTAIN_MSG), c('STUDYID', 'USUBJID', 'ROUTE', 'UNCERTAIN_MSG')]),
                              use.names=TRUE, fill=TRUE)
  }

  # Merge the list of extracted animals with the input set of animals to keep
  # any additional columns from the input table
  foundAnimals <-
    data.table::merge.data.table(animalList,
                                 foundAnimals,
                                 by=c('STUDYID', 'USUBJID'))

  # Do final preparation of set of found animals and return
  return(prepareFinalResults(foundAnimals,
                             names(animalList),
                             c('ROUTE'))  )
}

################################################################################
# Avoid  'no visible binding for global variable' notes from check of package:
ALL_ROUTE_EX <- ALL_ROUTE_TS <- ROUTE <- NULL
NUM_ROUTE <- NUM_ROUTE_EX <- NUM_ROUTE_TS <- NULL
