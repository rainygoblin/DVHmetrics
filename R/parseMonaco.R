#####---------------------------------------------------------------------------
## parse character vector from Eclipse DVH file
parseMonaco <- function(x, planInfo=FALSE, courseAsID=FALSE) {
    planInfo <- as.character(planInfo)

    ## extract file header and header info
    header   <- unlist(strsplit(x[1], " [|] "))
    patName  <- trimWS(sub("^Patient ID: (.+)[~].+$", "\\1", header[1]))
    patID    <- trimWS(sub("^Patient ID: .+[~](.+)$", "\\1", header[1]))
    plan     <- trimWS(sub("^Plan Name: (.+)$",       "\\1", header[2]))
    doseUnit <- toupper(trimWS(sub("^Dose Units: (.+)$", "\\1", header[5])))
    if(doseUnit == "%") {
        isDoseRel <- TRUE
        doseUnit  <- toupper(trimWS(sub("^Bin Width: [.[:digit:]]+\\((.+)\\)$", "\\1", header[4])))
    } else {
        isDoseRel <- FALSE
    }

    if(!grepl("^(GY|CGY)$", doseUnit)) {
        warning("Could not determine dose measurement unit")
        doseUnit <- NA_character_
    }

    volumeUnit <- toupper(trimWS(sub("^Volume Units: (.+)$", "\\1", header[6])))
    volumeUnit <- if(grepl("^CM.+", volumeUnit)) {
        isVolRel <- FALSE
        "CC"
    } else if(grepl("^%", volumeUnit)) {
        isVolRel <- TRUE
        "PERCENT"
    } else {
        isVolRel <- FALSE
        warning("Could not determine volume measurement unit")
        NA_character_
    }
    
    ## check if sum plan
    isoDoseRx  <- if(tolower(planInfo) == "doserx") {
        warning("Iso-dose-Rx is assumed to be 100")
        100
    } else {
        warning("No info on % for dose")
        NA_real_
    }

    doseRx <- if(tolower(planInfo) == "doserx") {
        drx <- sub("^[[:alnum:]]+_([.[:digit:]]+)(GY|CGY)_[[:alnum:]]*", "\\1",
                   plan, perl=TRUE, ignore.case=TRUE)
        as.numeric(drx)
    } else {
        warning("No info on prescribed dose")
        NA_real_
    }
    
    DVHdate <- x[length(x)]
#     footer <- x[length(x)]
#     lct <- Sys.getlocale("LC_TIME")
#     Sys.setlocale("LC_TIME", "C")
#     DVHdate <- tryCatch(as.Date(strptime(y, "%Y-%m-%d-%a %H:%M:%S")),
#                         error=function(e) { NA_character_ })
#     Sys.setlocale("LC_TIME", lct)

    DVHspan <- x[4:(length(x)-2)]
    con <- textConnection(DVHspan)
    DVHall <- read.table(con, header=FALSE, stringsAsFactors=FALSE)
    close(con)
    names(DVHall) <- if(isDoseRel) {
        if(isVolRel) {
            c("structure", "doseRel", "volumeRel")
        } else {
            c("structure", "doseRel", "volume")
        }
    } else {
        if(isVolRel) {
            c("structure", "dose", "volumeRel")
        } else {
            c("structure", "dose", "volume")
        }
    }

    structList <- split(DVHall, DVHall$structure)

    ## extract DVH from one structure section and store in a list
    ## with DVH itself as a matrix
    getDVH <- function(strct, info) {
        structure <- strct$structure[1]

        ## extract DVH as a matrix
        dvh <- data.matrix(strct[ , 2:3])
        haveVars <- colnames(dvh)

        ## add information we don't have yet
        ## relative/absolute volume/dose
        if(!("volume" %in% haveVars)) {
            isVolRel <- TRUE
            dvh <- cbind(dvh, volume=NA_real_)
        }

        if(!("volumeRel" %in% haveVars)) {
            isVolRel <- FALSE
            dvh <- cbind(dvh, volumeRel=NA_real_)
        }

        if(!("dose" %in% haveVars)) {
            dvh <- cbind(dvh, dose=NA_real_)
        }

        if(!("doseRel" %in% haveVars)) {
            dvh <- cbind(dvh, doseRel=NA_real_)
        }

        ## check if volume is already sorted -> cumulative DVH
        volume <- if(isVolRel) {
            dvh[ , "volumeRel"]
        } else {
            dvh[ , "volume"]
        }

        DVHtype <- if(isTRUE(all.equal(volume, sort(volume, decreasing=TRUE)))) {
            "cumulative"
        } else {
            "differential"
        }

        DVH <- list(dvh=dvh,
                    patName=info$patName,
                    patID=info$patID,
                    date=info$date,
                    DVHtype=DVHtype,
                    plan=info$plan,
                    structure=structure,
                    structVol=NA_real_,
                    doseUnit=info$doseUnit,
                    volumeUnit=info$volumeUnit,
                    doseRx=doseRx,
                    isoDoseRx=isoDoseRx,
                    doseMin=NA_real_,
                    doseMax=NA_real_,
                    doseAvg=NA_real_,
                    doseMed=NA_real_,
                    doseMode=NA_real_,
                    doseSD=NA_real_)

        ## convert differential DVH to cumulative
        ## and add differential DVH separately
        if(DVHtype == "differential") {
            DVH$dvh     <- convertDVH(dvh, toType="cumulative", toDoseUnit="asis")
            DVH$dvhDiff <- dvh
        }

        ## set class
        class(DVH) <- "DVHs"
        return(DVH)
    }

    ## list of DVH data frames with component name = structure
    info <- list(patID=patID, patName=patName, date=DVHdate,
                 plan=plan, doseRx=doseRx, isoDoseRx=isoDoseRx,
                 doseUnit=doseUnit, volumeUnit=volumeUnit)
    dvhL <- lapply(structList, getDVH, info=info)
    dvhL <- Filter(Negate(is.null), dvhL)
    names(dvhL) <- sapply(dvhL, function(y) y$structure)
    if(length(unique(names(dvhL))) < length(dvhL)) {
        warning("Some structures have the same name - this can lead to problems")
    }

    class(dvhL) <- "DVHLst"
    attr(dvhL, which="byPat") <- TRUE

    return(dvhL)
}