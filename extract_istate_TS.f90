program modif                                         
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
! Script to extract the temperature and salinity initial state from the parent grid
!
! 1- Read PARENT ("_PAR") mask
! 2- Read CHILD ("_CHLD") mask
! 3- Read PARENT temperature initial state
! 4- Read PARENT salinity initial state
! 5- Extract CHILD from PARENT
! 6- Writing CHILD initial state for temperature and salinity
!
! History: - Jan. 2017: initial version (N. Jourdain, CNRS-IGE)
!          - Nov. 2021 : + clarify PARENT/CHILD naming
!                        + write both T & S in single file 
!                        + remove nn_init option            (N. Jourdain)
!          - Jan. 2022: new convention for variable names (PAR/CHLD/EXT)
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

USE netcdf                                            

use gsw_mod_kinds
use gsw_mod_netcdf
use gsw_mod_toolbox

use gsw_mod_error_functions, only : gsw_error_code, gsw_error_limit

IMPLICIT NONE                                         

!-- namelist parameters :
namelist /general/ config, config_dir
namelist /init/ file_in_mask_extract, file_in_T, file_in_S, nn_eosmatch, nn_iter, nn_rsmax, nn_rzmax, &
&               rn_temp, rn_sal, nn_smooth, file_in_SI
INTEGER                               :: nn_iter, nn_rsmax, nn_rzmax, nn_eosmatch, nn_smooth
CHARACTER(LEN=50)                     :: config
CHARACTER(LEN=150)                    :: file_in_mask_extract, config_dir, file_in_T, file_in_S, file_in_SI
REAL(KIND=4)                          :: rn_temp, rn_sal

INTEGER :: fidMSKIN, fidMSKCHLD, status, dimID_z, dimID_y, dimID_x, mz_PAR, my_PAR, mx_PAR, tmask_PAR_ID, &
&          mx_CHLD, my_CHLD, mz_CHLD, tmask_CHLD_ID, fidSAL, fidTS, votemper_ID, vosaline_ID,                &
&          dimID_time_counter, ai, bi, aj, bj, iii, jjj, kkk, kk, iPAR, jPAR, iCHLD, jCHLD, fidTin, fidSin,&
&          kiter, rs, rz, sg, time_counter_ID, fidCOORD, imin_EXT, jmin_EXT, lon_ID, lat_ID, dij,  &
&          dep_ID, kPAR, ntest, im1, ip1, jm1, jp1

CHARACTER(LEN=180) :: file_in_mask_CHLD, file_in_coord_CHLD, file_out_TS

INTEGER*1,ALLOCATABLE,DIMENSION(:,:,:) :: tmask_PAR, tmask_CHLD, missing, tmp_missing

REAL(KIND=4),ALLOCATABLE,DIMENSION(:) ::  dep_PAR

REAL(KIND=4),ALLOCATABLE,DIMENSION(:,:) :: lon_PAR, lat_PAR

REAL(KIND=8),ALLOCATABLE,DIMENSION(:,:,:) :: votemper_PAR, vosaline_PAR, votemper_CHLD, vosaline_CHLD, &
&                                            tmp_votemper_CHLD, tmp_vosaline_CHLD

LOGICAL :: iout

!=================================================================================
! 0- Initializations 
!=================================================================================

call gsw_saar_init (.true.)

! Default values (replaced with namelist values if specified):
config_dir        = '.'
nn_iter           = 100
nn_rsmax          =   5
nn_rzmax          =   1
nn_eosmatch       =   1
nn_smooth         =   1
file_in_SI        = 'NOT USED'

!- read namelist values :
OPEN (UNIT=1, FILE='namelist_pre' )
READ (UNIT=1, NML=general)
READ (UNIT=1, NML=init)
CLOSE(1)

!- name of child mesh_mask (input) :
write(file_in_mask_CHLD,101) TRIM(config_dir), TRIM(config)
101 FORMAT(a,'/mesh_mask_',a,'.nc')

!- name of child coordinates (input) :
write(file_in_coord_CHLD,102) TRIM(config_dir), TRIM(config)
102 FORMAT(a,'/coordinates_',a,'.nc')

!- output file names :
write(file_out_TS,201)  TRIM(config_dir), TRIM(config)
201 FORMAT(a,'/istate_TS_',a,'.nc')

!=================================================================================
! 1- Read PARENT mask :                                 
!=================================================================================

status = NF90_OPEN(TRIM(file_in_mask_extract),0,fidMSKIN); call erreur(status,.TRUE.,"read mask input") 

status = NF90_INQ_DIMID(fidMSKIN,"z",dimID_z)
if ( status .ne. 0 ) status = NF90_INQ_DIMID(fidMSKIN,"nav_lev",dimID_z)
call erreur(status,.TRUE.,"inq_dimID_z_PAR")
status = NF90_INQ_DIMID(fidMSKIN,"y",dimID_y); call erreur(status,.TRUE.,"inq_dimID_y_PAR")
status = NF90_INQ_DIMID(fidMSKIN,"x",dimID_x); call erreur(status,.TRUE.,"inq_dimID_x_PAR")

status = NF90_INQUIRE_DIMENSION(fidMSKIN,dimID_z,len=mz_PAR); call erreur(status,.TRUE.,"inq_dim_z_PAR")
status = NF90_INQUIRE_DIMENSION(fidMSKIN,dimID_y,len=my_PAR); call erreur(status,.TRUE.,"inq_dim_y_PAR")
status = NF90_INQUIRE_DIMENSION(fidMSKIN,dimID_x,len=mx_PAR); call erreur(status,.TRUE.,"inq_dim_x_PAR")

ALLOCATE(  tmask_PAR(mx_PAR,my_PAR,mz_PAR)  ) 
ALLOCATE(  lon_PAR  (mx_PAR,my_PAR)  )
ALLOCATE(  lat_PAR  (mx_PAR,my_PAR)  )
ALLOCATE(  dep_PAR  (mz_PAR)  )

status = NF90_INQ_VARID(fidMSKIN,"tmask",tmask_PAR_ID); call erreur(status,.TRUE.,"inq_tmask_PAR_ID")
status = NF90_INQ_VARID(fidMSKIN,"nav_lon",lon_ID)    ; call erreur(status,.TRUE.,"inq_lon_PAR_ID")
status = NF90_INQ_VARID(fidMSKIN,"nav_lat",lat_ID)    ; call erreur(status,.TRUE.,"inq_lat_PAR_ID")
status = NF90_INQ_VARID(fidMSKIN,"nav_lev",dep_ID)    ; call erreur(status,.TRUE.,"inq_dep_PAR_ID")

status = NF90_GET_VAR(fidMSKIN,tmask_PAR_ID,tmask_PAR); call erreur(status,.TRUE.,"getvar_tmask_PAR")
status = NF90_GET_VAR(fidMSKIN,lon_ID,lon_PAR)        ; call erreur(status,.TRUE.,"getvar_lon_PAR")
status = NF90_GET_VAR(fidMSKIN,lat_ID,lat_PAR)        ; call erreur(status,.TRUE.,"getvar_lat_PAR")
status = NF90_GET_VAR(fidMSKIN,dep_ID,dep_PAR)        ; call erreur(status,.TRUE.,"getvar_dep_PAR")

status = NF90_CLOSE(fidMSKIN); call erreur(status,.TRUE.,"end read mask_PAR")

!=================================================================================
! 2- Read CHILD mask :
!=================================================================================

status = NF90_OPEN(TRIM(file_in_mask_CHLD),0,fidMSKCHLD); call erreur(status,.TRUE.,"read child mask") 

status = NF90_INQ_DIMID(fidMSKCHLD,"z",dimID_z)
if ( status .ne. 0 ) status = NF90_INQ_DIMID(fidMSKCHLD,"nav_lev",dimID_z)
call erreur(status,.TRUE.,"inq_dimID_z_CHLD")
status = NF90_INQ_DIMID(fidMSKCHLD,"y",dimID_y); call erreur(status,.TRUE.,"inq_dimID_y_CHLD")
status = NF90_INQ_DIMID(fidMSKCHLD,"x",dimID_x); call erreur(status,.TRUE.,"inq_dimID_x_CHLD")

status = NF90_INQUIRE_DIMENSION(fidMSKCHLD,dimID_z,len=mz_CHLD); call erreur(status,.TRUE.,"inq_dim_z_CHLD")
status = NF90_INQUIRE_DIMENSION(fidMSKCHLD,dimID_y,len=my_CHLD); call erreur(status,.TRUE.,"inq_dim_y_CHLD")
status = NF90_INQUIRE_DIMENSION(fidMSKCHLD,dimID_x,len=mx_CHLD); call erreur(status,.TRUE.,"inq_dim_x_CHLD")

ALLOCATE(  tmask_CHLD(mx_CHLD,my_CHLD,mz_CHLD)  ) 

status = NF90_INQ_VARID(fidMSKCHLD,"tmask",tmask_CHLD_ID); call erreur(status,.TRUE.,"inq_tmask_CHLD_ID")

status = NF90_GET_VAR(fidMSKCHLD,tmask_CHLD_ID,tmask_CHLD); call erreur(status,.TRUE.,"getvar_tmask_CHLD")

status = NF90_CLOSE(fidMSKCHLD); call erreur(status,.TRUE.,"end read fidMSKCHLD")

!=================================================================================
! 3- Read PARENT temperature initial state
!=================================================================================

write(*,*) 'where are we?'

status = NF90_OPEN(TRIM(file_in_T),0,fidTin); call erreur(status,.TRUE.,"read_T")        
ALLOCATE(  votemper_PAR(mx_PAR,my_PAR,mz_PAR)  )   
status = NF90_INQ_VARID(fidTin,"votemper",votemper_ID); call erreur(status,.TRUE.,"inq_votemper_PAR_ID")
status = NF90_GET_VAR(fidTin,votemper_ID,votemper_PAR); call erreur(status,.TRUE.,"getvar_votemper_PAR")
status = NF90_CLOSE(fidTin); call erreur(status,.TRUE.,"end_read_T") 

!=================================================================================
! 4- Read PARENT salinity initial state
!=================================================================================

write(*,*) 'where are we 2'

status = NF90_OPEN(TRIM(file_in_S),0,fidSin); call erreur(status,.TRUE.,"read_S")
ALLOCATE(  vosaline_PAR(mx_PAR,my_PAR,mz_PAR)  )
status = NF90_INQ_VARID(fidSin,"vosaline",vosaline_ID); call erreur(status,.TRUE.,"inq_vosaline_PAR_ID")
status = NF90_GET_VAR(fidSin,vosaline_ID,vosaline_PAR); call erreur(status,.TRUE.,"getvar_vosaline_PAR")
status = NF90_CLOSE(fidSin); call erreur(status,.TRUE.,"end_read_S") 

!- convert to conservative temperature if needed :
if ( nn_eosmatch .eq. 0 ) then
  write(*,*) 'Converting from EOS80 to TEOS10 ...'
  do iPAR=1,mx_PAR
  do jPAR=1,my_PAR
  do kPAR=1,mz_PAR
    if ( tmask_PAR(iPAR,jPAR,kPAR) .eq. 1 ) then
      vosaline_PAR(iPAR,jPAR,kPAR) = gsw_sa_from_sp( DBLE(vosaline_PAR(iPAR,jPAR,kPAR)), DBLE(dep_PAR(kPAR)), DBLE(lon_PAR(iPAR,jPAR)), DBLE(lat_PAR(iPAR,jPAR)) )
      votemper_PAR(iPAR,jPAR,kPAR) = gsw_ct_from_pt( DBLE(vosaline_PAR(iPAR,jPAR,kPAR)), DBLE(votemper_PAR(iPAR,jPAR,kPAR)) )
    else
      vosaline_PAR(iPAR,jPAR,kPAR) = 0.d0
      votemper_PAR(iPAR,jPAR,kPAR) = 0.d0
    endif
    if ( votemper_PAR(iPAR,jPAR,kPAR) .lt. -2.5 ) then
      write(*,*) '%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
      write(*,*) iPAR,jPAR,kPAR
      write(*,*) lon_PAR(iPAR,jPAR), lat_PAR(iPAR,jPAR), dep_PAR(kPAR)
      write(*,*) vosaline_PAR(iPAR,jPAR,kPAR), votemper_PAR(iPAR,jPAR,kPAR)
    endif
  enddo
  enddo
  enddo
elseif ( nn_eosmatch .ne. 1 ) then
  write(*,*) '~!@#$%^* Error: nn_eosmatch should be 0 or 1 >>>>> stop !!'
  stop
endif

!=================================================================================
! 5- Extract CHILD from PARENT
!=================================================================================

write(*,*) 'where are we 3'

ALLOCATE( votemper_CHLD(mx_CHLD,my_CHLD,mz_CHLD) )
ALLOCATE( vosaline_CHLD(mx_CHLD,my_CHLD,mz_CHLD) )

if ( mz_CHLD .ne. mz_PAR ) then
  write(*,*) '~!@#$%^ Adapt script for different number of vertical levels >>>> Stop!!'
  stop
endif

!- Read global attributes of coordinate file to get grid correspondance :
!       i_EXT = ai * i_PAR + bi
!       j_EXT = aj * j_PAR + bj
status = NF90_OPEN(TRIM(file_in_coord_CHLD),0,fidCOORD); call erreur(status,.TRUE.,"read coord input")
status = NF90_GET_ATT(fidCOORD, NF90_GLOBAL, "ai", ai); call erreur(status,.TRUE.,"read att1")
status = NF90_GET_ATT(fidCOORD, NF90_GLOBAL, "bi", bi); call erreur(status,.TRUE.,"read att2")
status = NF90_GET_ATT(fidCOORD, NF90_GLOBAL, "aj", aj); call erreur(status,.TRUE.,"read att3")
status = NF90_GET_ATT(fidCOORD, NF90_GLOBAL, "bj", bj); call erreur(status,.TRUE.,"read att4")
status = NF90_GET_ATT(fidCOORD, NF90_GLOBAL, "imin_extraction", imin_EXT); call erreur(status,.TRUE.,"read att5")
status = NF90_GET_ATT(fidCOORD, NF90_GLOBAL, "jmin_extraction", jmin_EXT); call erreur(status,.TRUE.,"read att6")
status = NF90_CLOSE(fidCOORD)                         ; call erreur(status,.TRUE.,"end read fidCOORD")

! Just extract where ocean points on both grids :
ALLOCATE( missing(mx_CHLD,my_CHLD,mz_CHLD) )
ALLOCATE( tmp_missing(mx_CHLD,my_CHLD,mz_CHLD) )
ALLOCATE( tmp_votemper_CHLD(mx_CHLD,my_CHLD,mz_CHLD) )
ALLOCATE( tmp_vosaline_CHLD(mx_CHLD,my_CHLD,mz_CHLD) )
missing(:,:,:)=0
votemper_CHLD(:,:,:)=0.d0
vosaline_CHLD(:,:,:)=0.d0
do iCHLD=1,mx_CHLD
do jCHLD=1,my_CHLD
   iPAR=NINT(FLOAT(iCHLD+imin_EXT-1-bi)/ai)
   jPAR=NINT(FLOAT(jCHLD+jmin_EXT-1-bj)/aj)
   if ( iPAR .ge. 1 .and. jPAR .ge. 1 ) then
     do kk=1,mz_CHLD
       if ( tmask_PAR(iPAR,jPAR,kk) .eq. 1 ) then
         votemper_CHLD(iCHLD,jCHLD,kk) = votemper_PAR(iPAR,jPAR,kk) * tmask_CHLD(iCHLD,jCHLD,kk) 
         vosaline_CHLD(iCHLD,jCHLD,kk) = vosaline_PAR(iPAR,jPAR,kk) * tmask_CHLD(iCHLD,jCHLD,kk) 
       elseif ( tmask_CHLD(iCHLD,jCHLD,kk) .eq. 1 ) then ! unmasked CHLD but masked PAR
         missing(iCHLD,jCHLD,kk) = 1
       endif
     enddo
   else ! part of the child domain not covered by the global domain
     do kk=1,mz_CHLD
       if ( tmask_CHLD(iCHLD,jCHLD,kk) .eq. 1 ) missing(iCHLD,jCHLD,kk) = 1
     enddo
   endif
enddo
enddo

! Look for closest neighbours where we have missing values:
write(*,*) 'where are we 4'
do kiter=1,nn_iter

write(*,*) 'is this the problem again'

  ntest = NINT(sum(sum(sum(FLOAT(missing),3),2),1))
  write(*,*) '  kiter = ', kiter
  write(*,*) '     nb of pts with missing value: ', ntest
 if ( ntest .eq. 0 ) exit
  tmp_votemper_CHLD(:,:,:)=votemper_CHLD(:,:,:)
  tmp_vosaline_CHLD(:,:,:)=vosaline_CHLD(:,:,:)
  tmp_missing(:,:,:)=missing(:,:,:)
  do iCHLD=1,mx_CHLD
  do jCHLD=1,my_CHLD
  do kk=1,mz_CHLD
    if ( missing(iCHLD,jCHLD,kk) .eq. 1 ) then
      iout=.FALSE.
      do rz=0,nn_rzmax,1
      do sg=-1,1,2 ! to look above first, then below
        do rs=1,nn_rsmax,1
          iii=iCHLD               ; jjj=jCHLD               ; kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD) ! to look right above/below
          if ( tmask_CHLD(iii,jjj,kkk) .eq. 1 .and. missing(iii,jjj,kkk) .eq. 0 ) then ; iout=.TRUE. ; exit ; endif
          iii=MIN(iCHLD+rs,mx_CHLD); jjj=jCHLD               ; kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD)
          if ( tmask_CHLD(iii,jjj,kkk) .eq. 1 .and. missing(iii,jjj,kkk) .eq. 0 ) then ; iout=.TRUE. ; exit ; endif
          iii=MAX(iCHLD-rs,1)     ; jjj=jCHLD               ; kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD)
          if ( tmask_CHLD(iii,jjj,kkk) .eq. 1 .and. missing(iii,jjj,kkk) .eq. 0 ) then ; iout=.TRUE. ; exit ; endif
          iii=iCHLD               ; jjj=MIN(jCHLD+rs,my_CHLD); kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD)
          if ( tmask_CHLD(iii,jjj,kkk) .eq. 1 .and. missing(iii,jjj,kkk) .eq. 0 ) then ; iout=.TRUE. ; exit ; endif
          iii=iCHLD               ; jjj=MAX(jCHLD-rs,1)     ; kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD)
          if ( tmask_CHLD(iii,jjj,kkk) .eq. 1 .and. missing(iii,jjj,kkk) .eq. 0 ) then ; iout=.TRUE. ; exit ; endif
          iii=MIN(iCHLD+rs,mx_CHLD); jjj=MIN(jCHLD+rs,my_CHLD); kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD)
          if ( tmask_CHLD(iii,jjj,kkk) .eq. 1 .and. missing(iii,jjj,kkk) .eq. 0 ) then ; iout=.TRUE. ; exit ; endif
          iii=MIN(iCHLD+rs,mx_CHLD); jjj=MAX(jCHLD-rs,1)     ; kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD)
          if ( tmask_CHLD(iii,jjj,kkk) .eq. 1 .and. missing(iii,jjj,kkk) .eq. 0 ) then ; iout=.TRUE. ; exit ; endif
          iii=MAX(iCHLD-rs,1)     ; jjj=MIN(jCHLD+rs,my_CHLD); kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD) 
          if ( tmask_CHLD(iii,jjj,kkk) .eq. 1 .and. missing(iii,jjj,kkk) .eq. 0 ) then ; iout=.TRUE. ; exit ; endif
          iii=MAX(iCHLD-rs,1)     ; jjj=MAX(jCHLD-rs,1)     ; kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD) 
          if ( tmask_CHLD(iii,jjj,kkk) .eq. 1 .and. missing(iii,jjj,kkk) .eq. 0 ) then
            iout=.TRUE.
            exit
          endif
        enddo !- rs
        if (iout) exit
      enddo !-sg
      if (iout) then
        tmp_missing(iCHLD,jCHLD,kk) = 0
        tmp_votemper_CHLD(iCHLD,jCHLD,kk) = votemper_CHLD(iii,jjj,kkk)
        tmp_vosaline_CHLD(iCHLD,jCHLD,kk) = vosaline_CHLD(iii,jjj,kkk)
        exit
      elseif ( ( rz .eq. nn_rzmax .and. kiter .eq. nn_iter ) .or. nn_rzmax .eq. 0 ) then
        write(*,953) iCHLD, jCHLD, kk
        953 FORMAT(' >>> WARNING for point (',3I5,') --> filled with rn_temp and rn_sal (to avoid this, increase nn_rsmax and/or nn_rzmax and/or nn_iter)')
        tmp_missing(iCHLD,jCHLD,kk) = 0
        tmp_votemper_CHLD(iCHLD,jCHLD,kk) = rn_temp
        tmp_vosaline_CHLD(iCHLD,jCHLD,kk) = rn_sal
        exit
      endif
      enddo !-rz
    endif !-if ( missing(iCHLD,jCHLD,kk) .eq. 1 )
  enddo !- kk
  enddo !- jCHLD
  enddo !- iCHLD
  missing(:,:,:)=tmp_missing(:,:,:)
  votemper_CHLD(:,:,:)=tmp_votemper_CHLD(:,:,:)
  vosaline_CHLD(:,:,:)=tmp_vosaline_CHLD(:,:,:)
enddo !- kiter

write(*,*) 'no more crashes?'

!- Smoothing :
if ( nn_smooth .gt. 1 ) then
  write(*,*) 'Smoothing window width = ', nn_smooth
  dij=INT(nn_smooth*0.5)
  tmp_votemper_CHLD(:,:,:)=votemper_CHLD(:,:,:)
  tmp_vosaline_CHLD(:,:,:)=vosaline_CHLD(:,:,:)
  do iCHLD=1,mx_CHLD
  do jCHLD=1,my_CHLD
  do kk=1,mz_CHLD
    im1=MAX(iCHLD-dij,1) ; ip1=MIN(iCHLD+dij,mx_CHLD) 
    jm1=MAX(jCHLD-dij,1) ; jp1=MIN(jCHLD+dij,my_CHLD)
    if ( tmask_CHLD(iCHLD,jCHLD,kk) .eq. 1 ) then 
      tmp_votemper_CHLD(iCHLD,jCHLD,kk) =   SUM( SUM( votemper_CHLD(im1:ip1,jm1:jp1,kk) * tmask_CHLD(im1:ip1,jm1:jp1,kk), 2), 1) &
      &                                / SUM( SUM(                             1.0  * tmask_CHLD(im1:ip1,jm1:jp1,kk), 2), 1)
      tmp_vosaline_CHLD(iCHLD,jCHLD,kk) =   SUM( SUM( vosaline_CHLD(im1:ip1,jm1:jp1,kk) * tmask_CHLD(im1:ip1,jm1:jp1,kk), 2), 1) &
      &                                / SUM( SUM(                             1.0  * tmask_CHLD(im1:ip1,jm1:jp1,kk), 2), 1)
    else
      tmp_votemper_CHLD(iCHLD,jCHLD,kk) = 0.d0
      tmp_vosaline_CHLD(iCHLD,jCHLD,kk) = 0.d0
    endif
  enddo
  enddo
  enddo
  votemper_CHLD(:,:,:)=tmp_votemper_CHLD(:,:,:)
  vosaline_CHLD(:,:,:)=tmp_vosaline_CHLD(:,:,:)
else
  write(*,*) 'No Smoothing'
endif

!- "Drowning", i.e. put closest value everywhere on the mask file to avoid issue if namdom is slightly changed :
!  We just repeat the previous methodology, but for masked points
write(*,*) 'Drowning, i.e. fill all masked points with closest neighbour'
missing(:,:,:)=NINT(1-FLOAT(tmask_CHLD(:,:,:)))
! Look for closest neighbours where we have missing values:
do kiter=1,nn_iter
  ntest = NINT(sum(sum(sum(FLOAT(missing),3),2),1))
  write(*,*) '  kiter = ', kiter
  write(*,*) '     remaining nb of masked points to fill: ', ntest
  if ( ntest .eq. 0 ) exit
  tmp_votemper_CHLD(:,:,:)=votemper_CHLD(:,:,:)
  tmp_vosaline_CHLD(:,:,:)=vosaline_CHLD(:,:,:)
  tmp_missing(:,:,:)=missing(:,:,:)
  do iCHLD=1,mx_CHLD
  do jCHLD=1,my_CHLD
  do kk=1,mz_CHLD
    if ( missing(iCHLD,jCHLD,kk) .eq. 1 ) then
      iout=.FALSE.
      do rz=0,nn_rzmax,1
      do sg=-1,1,2 ! to look above first, then below
        do rs=1,nn_rsmax,1
          iii=iCHLD               ; jjj=jCHLD               ; kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD) ! to look right above/below
          if ( missing(iii,jjj,kkk) .eq. 0 ) then ; iout=.TRUE. ; exit ; endif
          iii=MIN(iCHLD+rs,mx_CHLD); jjj=jCHLD               ; kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD)
          if ( missing(iii,jjj,kkk) .eq. 0 ) then ; iout=.TRUE. ; exit ; endif
          iii=MAX(iCHLD-rs,1)     ; jjj=jCHLD               ; kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD)
          if ( missing(iii,jjj,kkk) .eq. 0 ) then ; iout=.TRUE. ; exit ; endif
          iii=iCHLD               ; jjj=MIN(jCHLD+rs,my_CHLD); kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD)
          if ( missing(iii,jjj,kkk) .eq. 0 ) then ; iout=.TRUE. ; exit ; endif
          iii=iCHLD               ; jjj=MAX(jCHLD-rs,1)     ; kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD)
          if ( missing(iii,jjj,kkk) .eq. 0 ) then ; iout=.TRUE. ; exit ; endif
          iii=MIN(iCHLD+rs,mx_CHLD); jjj=MIN(jCHLD+rs,my_CHLD); kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD)
          if ( missing(iii,jjj,kkk) .eq. 0 ) then ; iout=.TRUE. ; exit ; endif
          iii=MIN(iCHLD+rs,mx_CHLD); jjj=MAX(jCHLD-rs,1)     ; kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD)
          if ( missing(iii,jjj,kkk) .eq. 0 ) then ; iout=.TRUE. ; exit ; endif
          iii=MAX(iCHLD-rs,1)     ; jjj=MIN(jCHLD+rs,my_CHLD); kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD) 
          if ( missing(iii,jjj,kkk) .eq. 0 ) then ; iout=.TRUE. ; exit ; endif
          iii=MAX(iCHLD-rs,1)     ; jjj=MAX(jCHLD-rs,1)     ; kkk= MIN(MAX(kk+rz*sg,1),mz_CHLD) 
          if ( missing(iii,jjj,kkk) .eq. 0 ) then ; iout=.TRUE. ; exit ; endif
        enddo !- rs
        if (iout) exit
      enddo !-sg
      if (iout) then
        tmp_missing(iCHLD,jCHLD,kk) = 0
        tmp_votemper_CHLD(iCHLD,jCHLD,kk) = votemper_CHLD(iii,jjj,kkk)
        tmp_vosaline_CHLD(iCHLD,jCHLD,kk) = vosaline_CHLD(iii,jjj,kkk)
        exit
      elseif ( rz .eq. nn_rzmax .and. kiter .eq. nn_iter ) then
        tmp_missing(iCHLD,jCHLD,kk) = 0
        tmp_votemper_CHLD(iCHLD,jCHLD,kk) = rn_temp
        tmp_vosaline_CHLD(iCHLD,jCHLD,kk) = rn_sal
        exit
      endif
      enddo !-rz
    endif !-if ( missing(iCHLD,jCHLD,kk) .eq. 1 )
  enddo !- kk
  enddo !- jCHLD
  enddo !- iCHLD
  missing(:,:,:)=tmp_missing(:,:,:)
  votemper_CHLD(:,:,:)=tmp_votemper_CHLD(:,:,:)
  vosaline_CHLD(:,:,:)=tmp_vosaline_CHLD(:,:,:)
enddo !- kiter

!--  
DEALLOCATE( tmp_votemper_CHLD, tmp_vosaline_CHLD, missing )

!=================================================================================
! 6- Writing CHILD initial state for temperature and salinity 
!=================================================================================

write(*,*) 'Writing ', TRIM(file_out_TS)

status = NF90_CREATE(TRIM(file_out_TS),NF90_NOCLOBBER,fidTS) ; call erreur(status,.TRUE.,'create output temp')

status = NF90_DEF_DIM(fidTS,"time_counter",NF90_UNLIMITED,dimID_time_counter) ; call erreur(status,.TRUE.,"def_dimID_time_counter")
status = NF90_DEF_DIM(fidTS,"x",mx_CHLD,dimID_x)                               ; call erreur(status,.TRUE.,"def_dimID_x")
status = NF90_DEF_DIM(fidTS,"y",my_CHLD,dimID_y)                               ; call erreur(status,.TRUE.,"def_dimID_y")
status = NF90_DEF_DIM(fidTS,"z",mz_CHLD,dimID_z)                               ; call erreur(status,.TRUE.,"def_dimID_deptht")

status = NF90_DEF_VAR(fidTS,"time_counter",NF90_DOUBLE,(/dimID_time_counter/),time_counter_ID)
call erreur(status,.TRUE.,"def_var_time_counter_ID")
status = NF90_DEF_VAR(fidTS,"votemper",NF90_FLOAT,(/dimID_x,dimID_y,dimID_z,dimID_time_counter/),votemper_ID)
call erreur(status,.TRUE.,"def_var_votemper_ID")
status = NF90_DEF_VAR(fidTS,"vosaline",NF90_FLOAT,(/dimID_x,dimID_y,dimID_z,dimID_time_counter/),vosaline_ID)
call erreur(status,.TRUE.,"def_var_vosaline_ID")

status = NF90_PUT_ATT(fidTS,votemper_ID,"associate","time_counter, z, y, x") ; call erreur(status,.TRUE.,"put_att_votemper_ID")
status = NF90_PUT_ATT(fidTS,votemper_ID,"missing_value",0.)                  ; call erreur(status,.TRUE.,"put_att_votemper_ID")
status = NF90_PUT_ATT(fidTS,votemper_ID,"_FillValue",0.)                     ; call erreur(status,.TRUE.,"put_att_votemper_ID")
status = NF90_PUT_ATT(fidTS,votemper_ID,"units","degC")                      ; call erreur(status,.TRUE.,"put_att_votemper_ID")
status = NF90_PUT_ATT(fidTS,votemper_ID,"long_name","conservative temperature") ; call erreur(status,.TRUE.,"put_att_votemper_ID")
! status = NF90_PUT_ATT(fidTS,votemper_ID,"long_name","potential temperature")    ; call erreur(status,.TRUE.,"put_att_votemper_ID") 

status = NF90_PUT_ATT(fidTS,vosaline_ID,"associate","time_counter, z, y, x") ; call erreur(status,.TRUE.,"put_att_vosaline_ID")
status = NF90_PUT_ATT(fidTS,vosaline_ID,"missing_value",0.)                  ; call erreur(status,.TRUE.,"put_att_vosaline_ID")
status = NF90_PUT_ATT(fidTS,vosaline_ID,"_FillValue",0.)                     ; call erreur(status,.TRUE.,"put_att_vosaline_ID")
status = NF90_PUT_ATT(fidTS,vosaline_ID,"units","g/kg")                    ; call erreur(status,.TRUE.,"put_att_vosaline_ID")
status = NF90_PUT_ATT(fidTS,vosaline_ID,"long_name","absolute salinity")   ; call erreur(status,.TRUE.,"put_att_vosaline_ID")
! status = NF90_PUT_ATT(fidTS,vosaline_ID,"units","psu")                     ; call erreur(status,.TRUE.,"put_att_vosaline_ID")
! status = NF90_PUT_ATT(fidTS,vosaline_ID,"long_name","practical salinity")  ; call erreur(status,.TRUE.,"put_att_vosaline_ID")

status = NF90_PUT_ATT(fidTS,time_counter_ID,"title","Time")                  ; call erreur(status,.TRUE.,"put_att_time_counter_ID")
status = NF90_PUT_ATT(fidTS,time_counter_ID,"long_name","Time axis")         ; call erreur(status,.TRUE.,"put_att_time_counter_ID")
status = NF90_PUT_ATT(fidTS,time_counter_ID,"standard_name","time")          ; call erreur(status,.TRUE.,"put_att_time_counter_ID")
status = NF90_PUT_ATT(fidTS,time_counter_ID,"axis","T")                      ; call erreur(status,.TRUE.,"put_att_time_counter_ID")

status = NF90_PUT_ATT(fidTS,NF90_GLOBAL,"history","Created using extract_istate_TS.f90")
status = NF90_PUT_ATT(fidTS,NF90_GLOBAL,"tools","https://github.com/nicojourdain/BUILD_CONFIG_NEMO")
call erreur(status,.TRUE.,"put_att_GLOBAL")

status = NF90_ENDDEF(fidTS) ; call erreur(status,.TRUE.,"end_definition") 

status = NF90_PUT_VAR(fidTS,time_counter_ID,1.0)       ; call erreur(status,.TRUE.,"var_time_counter_ID")
status = NF90_PUT_VAR(fidTS,votemper_ID,votemper_CHLD)  ; call erreur(status,.TRUE.,"var_votemper_ID")
status = NF90_PUT_VAR(fidTS,vosaline_ID,vosaline_CHLD)  ; call erreur(status,.TRUE.,"var_vosaline_ID")

status = NF90_CLOSE(fidTS) ; call erreur(status,.TRUE.,"final")         


end program modif



SUBROUTINE erreur(iret, lstop, chaine)
! pour les messages d'erreur
USE netcdf
INTEGER, INTENT(in)                     :: iret
LOGICAL, INTENT(in)                     :: lstop
CHARACTER(LEN=*), INTENT(in)            :: chaine
!
CHARACTER(LEN=80)                       :: message
!
IF ( iret .NE. 0 ) THEN
WRITE(*,*) 'MESSAGE: ', TRIM(chaine)
WRITE(*,*) 'ERROR: ', iret
message=NF90_STRERROR(iret)
WRITE(*,*) 'WHICH MEANS:',TRIM(message)
IF ( lstop ) STOP
ENDIF
!
END SUBROUTINE erreur
