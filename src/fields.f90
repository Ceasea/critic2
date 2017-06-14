! Copyright (c) 2015 Alberto Otero de la Roza <aoterodelaroza@gmail.com>,
! Ángel Martín Pendás <angel@fluor.quimica.uniovi.es> and Víctor Luaña
! <victor@fluor.quimica.uniovi.es>.
!
! critic2 is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or (at
! your option) any later version.
!
! critic2 is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.

! Evaluation of scalar fields
module fields
  use types, only: integrable, pointpropable, field
  implicit none

  private

  integer, parameter, public :: type_promol = 0 !< promolecular density
  integer, parameter, public :: type_grid = 1 !< grid format
  integer, parameter, public :: type_wien = 2 !< wien2k format
  integer, parameter, public :: type_elk  = 3 !< elk format
  integer, parameter, public :: type_pi   = 4 !< pi format
  integer, parameter, public :: type_wfn  = 6 !< molecular wavefunction format
  integer, parameter, public :: type_dftb = 7 !< DFTB+ wavefunction
  integer, parameter, public :: type_promol_frag = 8 !< promolecular density from a fragment
  integer, parameter, public :: type_ghost = 9 !< a ghost field

  public :: fields_load
  public :: fields_load_real
  public :: fields_unload
  public :: fields_init
  public :: fields_end
  public :: fields_propty
  public :: fields_integrable
  public :: fields_integrable_report
  public :: fields_pointprop
  public :: fields_pointprop_report
  public :: listfields
  public :: listfieldalias
  public :: writegrid_cube
  public :: writegrid_vasp
  public :: goodfield
  public :: getfieldnum
  public :: setfield
  public :: grd
  public :: grd0
  public :: grdall
  public :: fields_typestring
  public :: benchmark
  public :: taufromelf
  public :: testrmt
  public :: fieldname_to_idx
  public :: fieldinfo
  public :: fields_fcheck
  public :: fields_feval
  private :: der1i
  private :: der2ii
  private :: der2ij

  ! integrable properties
  integer, public :: nprops
  type(integrable), allocatable, public :: integ_prop(:)
  integer, parameter, public :: itype_v = 1
  integer, parameter, public :: itype_f = 2
  integer, parameter, public :: itype_fval = 3
  integer, parameter, public :: itype_gmod = 4
  integer, parameter, public :: itype_lap = 5
  integer, parameter, public :: itype_lapval = 6
  integer, parameter, public :: itype_expr = 7
  integer, parameter, public :: itype_mpoles = 8
  integer, parameter, public :: itype_deloc = 9
  character*10, parameter, public :: itype_names(9) = (/&
     "Volume    ","Field     ","Field (v) ","Gradnt mod","Laplacian ",&
     "Laplcn (v)","Expression","Multipoles","Deloc indx"/)
  
  ! pointprop properties
  integer, public :: nptprops
  type(pointpropable), allocatable, public :: point_prop(:)

  ! scalar fields
  type(field), allocatable, public :: f(:)
  logical, allocatable, public :: fused(:)

  ! eps to move to the main cell
  real*8, parameter :: flooreps = 1d-4 ! border around unit cell

  ! numerical differentiation
  real*8, parameter :: derw = 1.4d0, derw2 = derw*derw, big = 1d30, safe = 2d0
  integer, parameter :: ndif_jmax = 10

contains

  !> Initialize the module variable for the fields.
  subroutine fields_init()
    use param, only: fh

    integer :: i

    integer, parameter :: mf = 1
    
    ! allocate space for all fields
    if (.not.allocated(fused)) allocate(fused(0:mf))
    fused = .false.
    if (.not.allocated(f)) allocate(f(0:mf))
    do i = 0, mf
       f(i)%init = .false.
       f(i)%numerical = .false.
    end do

    ! allocate space for integrable
    if (allocated(integ_prop)) deallocate(integ_prop)
    allocate(integ_prop(10))

    ! initialize the promolecular density
    f(0)%init = .true.
    f(0)%iswan = .false.
    f(0)%type = type_promol
    f(0)%usecore = .false.
    f(0)%typnuc = -3
    fused(0) = .true.
    call fh%put("rho0",0)
    call fh%put("0",0)

    ! integrable properties, initialize
    nprops = 1
    integ_prop(:)%used = .false.

    ! point properties, initialize
    nptprops = 0
    if (allocated(point_prop)) deallocate(point_prop)
    allocate(point_prop(10))

    ! integrable: volume
    integ_prop(1)%used = .true.
    integ_prop(1)%itype = itype_v
    integ_prop(1)%fid = 0
    integ_prop(1)%prop_name = "Volume"

  end subroutine fields_init

  !> Terminate the variable allocations for the fields.
  subroutine fields_end()
    use param, only: fh

    if (allocated(fused)) deallocate(fused)
    if (allocated(f)) deallocate(f)
    call fh%free()

  end subroutine fields_end

  !> Load a field - parse copy and allocate slot
  subroutine fields_load(line,id,oksyn)
    use tools_io, only: getword, equal, ferror, faterr, lgetword, string
    use types, only: realloc
    use param, only: fh

    character*(*), intent(in) :: line
    integer, intent(out) :: id
    logical, intent(out) :: oksyn

    integer :: lp, lp2, oid, id2
    character(len=:), allocatable :: file, word
    logical :: dormt

    ! read and parse
    oksyn = .false.
    lp=1
    file = getword(line,lp)

    ! if it is one of the special keywords, change the extension
    ! and read the next
    if (equal(file,"copy")) then
       word = getword(line,lp)
       oid = fieldname_to_idx(word)
       if (oid < 0) then
          call ferror("fields_load","wrong LOAD COPY syntax",faterr,line,syntax=.true.)
          return
       end if
       lp2 = lp
       word = lgetword(line,lp)
       if (equal(word,'to')) then
          word = getword(line,lp)
          id = fieldname_to_idx(word)
          if (id < 0) then
             call ferror("fields_load","erroneous field id in LOAD COPY",faterr,line,syntax=.true.)
             return
          end if
          if (id > ubound(f,1)) then
             id2 = ubound(f,1)
             call realloc(fused,id)
             call realloc(f,id)
             fused(id2+1:) = .false.
          end if
          if (fused(id)) call fields_unload(id)
          if (fh%iskey(trim(word))) call fh%put(trim(word),id)
       else
          id = getfieldnum()
          lp = lp2
       end if
       f(id) = f(oid)
       fused(id) = .true.
       call fh%put(string(id),id)

       ! parse the rest of the line
       call setfield(f(id),id,line(lp:),oksyn)
       if (.not.oksyn) return
    else
       ! allocate slot
       id = getfieldnum()

       ! load the field
       f(id) = fields_load_real(line,id,oksyn,dormt)
       if (.not.oksyn) return

       ! test the muffin tin discontinuity, if applicable
       if (dormt) &
          call testrmt(id,0)
    endif
    oksyn = .true.

    call fieldinfo(id,.true.,.true.)

  end subroutine fields_load

  !> Load a field - parse the line (line) and call the appropriate
  !> reader.  fid is the slot where the field will be saved. oksyn is
  !> true in output if the syntax was correct. dormt is true if the MT
  !> discontinuity test for elk/wien2k needs to be run.
  function fields_load_real(line,fid,oksyn,dormt) result(ff)
    use dftb_private, only: dftb_read, dftb_register_struct
    use elk_private, only: elk_read_out, elk_tolap
    use wien_private, only: wien_read_clmsum, wien_tolap
    use wfn_private, only: wfn_read_wfn, wfn_register_struct, wfn_read_fchk, wfn_read_molden,&
       wfn_read_wfx
    use pi_private, only: pi_read_ion, pi_register_struct, fillinterpol
    use crystalmod, only: cr
    use grid_tools, only: mode_tricubic, grid_read_cube, grid_read_abinit, grid_read_siesta,&
       grid_read_vasp, grid_read_qub, grid_read_xsf, grid_read_elk, grid_rhoat, &
       grid_laplacian, grid_gradrho, grid_read_unk, grid_read_unkgen
    use global, only: eval_next
    use arithmetic, only: eval, fields_in_eval
    use tools_io, only: getword, equal, ferror, faterr, lgetword, zatguess, isinteger,&
       isexpression_or_word, string, lower
    use types, only: fragment
    use param, only: dirsep, eye

    character*(*), intent(in) :: line
    integer, intent(in) :: fid
    logical, intent(out) :: oksyn
    logical, intent(out) :: dormt
    type(field) :: ff

    integer :: lp, lp2, i, j, id, id1, id2
    character(len=:), allocatable :: file, lfile, file2, file3, file4, lword
    character(len=:), allocatable :: wext1, wext2, word, word2, expr
    integer :: zz, n(3)
    logical :: ok, nou, nochk
    real*8 :: renv0(3,cr%nenv), xp(3), rhopt
    integer :: idx0(cr%nenv), zenv0(cr%nenv), lenv0(3,cr%nenv)
    integer :: ix, iy, iz, oid
    real*8 :: xd(3,3), mcut, wancut
    integer :: nid, nword
    character*255, allocatable :: idlist(:)
    type(fragment) :: fr
    logical :: isfrag, iok

    ! check that we have an environment
    call cr%checkflags(.true.,env0=.true.)

    ! defaults
    dormt = .true.
    ff%iswan = .false.

    ! read and parse
    oksyn = .false.
    lp=1
    file = getword(line,lp)
    lfile = lower(file)
    word = file(index(file,dirsep,.true.)+1:)
    wext1 = word(index(word,'.',.true.)+1:)
    word = file(index(file,dirsep,.true.)+1:)
    wext2 = word(index(word,'_',.true.)+1:)

    ! if it is one of the special keywords, change the extension
    ! and read the next
    if (equal(lfile,"wien")) then
       file = getword(line,lp)
       wext1 = "clmsum"
       wext2 = wext1
    elseif (equal(lfile,"elk")) then
       file = getword(line,lp)
       wext1 = "OUT"
       wext2 = wext1
    elseif (equal(lfile,"pi")) then
       file = getword(line,lp)
       wext1 = "ion"
       wext2 = wext1
    elseif (equal(lfile,"cube")) then
       file = getword(line,lp)
       wext1 = "cube"
       wext2 = wext1
    elseif (equal(lfile,"abinit")) then
       file = getword(line,lp)
       wext1 = "DEN"
       wext2 = wext1
    elseif (equal(lfile,"vasp")) then
       file = getword(line,lp)
       wext1 = "CHGCAR"
       wext2 = wext1
    elseif (equal(lfile,"vaspchg")) then
       file = getword(line,lp)
       wext1 = "CHG"
       wext2 = wext1
    elseif (equal(lfile,"qub")) then
       file = getword(line,lp)
       wext1 = "qub"
       wext2 = wext1
    elseif (equal(lfile,"xsf")) then
       file = getword(line,lp)
       wext1 = "xsf"
       wext2 = wext1
    elseif (equal(lfile,"elkgrid")) then
       file = getword(line,lp)
       wext1 = "grid"
       wext2 = wext1
    elseif (equal(lfile,"siesta")) then
       file = getword(line,lp)
       wext1 = "RHO"
       wext2 = wext1
    elseif (equal(lfile,"dftb")) then
       file = getword(line,lp)
       wext1 = "xml"
       wext2 = wext1
    elseif (equal(lfile,"chk")) then
       file = ""
       wext1 = "chk"
       wext2 = wext1
    elseif (equal(lfile,"as")) then
       file = ""
       wext1 = "as"
       wext2 = wext1
    elseif (equal(lfile,"copy")) then
       call ferror('fields_load_real','can not copy in fields_load_real',faterr)
    end if

    if (equal(wext1,'cube')) then
       call grid_read_cube(file,ff)
       ff%type = type_grid
       ff%file = file
    else if (equal(wext1,'DEN').or.equal(wext2,'DEN').or.equal(wext1,'ELF').or.equal(wext2,'ELF').or.&
       equal(wext1,'POT').or.equal(wext2,'POT').or.equal(wext1,'VHA').or.equal(wext2,'VHA').or.&
       equal(wext1,'VHXC').or.equal(wext2,'VHXC').or.equal(wext1,'VXC').or.equal(wext2,'VXC').or.&
       equal(wext1,'GDEN1').or.equal(wext2,'GDEN1').or.equal(wext1,'GDEN2').or.equal(wext2,'GDEN2').or.&
       equal(wext1,'GDEN3').or.equal(wext2,'GDEN3').or.equal(wext1,'LDEN').or.equal(wext2,'LDEN').or.&
       equal(wext1,'KDEN').or.equal(wext2,'KDEN').or.equal(wext1,'PAWDEN').or.equal(wext2,'PAWDEN')) then
       call grid_read_abinit(file,ff)
       ff%type = type_grid
       ff%file = file
    else if (equal(wext1,'RHO') .or. equal(wext1,'BADER') .or.&
       equal(wext1,'DRHO') .or. equal(wext1,'LDOS') .or.&
       equal(wext1,'VT') .or. equal(wext1,'VH')) then
       call grid_read_siesta(file,ff)
       ff%type = type_grid
       ff%file = file
    else if (equal(wext1,'xml')) then
       ! array for the atomic numbers
       do i = 1, cr%ncel
          zenv0(i) = cr%at(cr%atcel(i)%idx)%z
       end do

       ! read the field
       file2 = getword(line,lp)
       file3 = getword(line,lp)
       call dftb_read(ff,file,file2,file3,zenv0(1:cr%ncel))
       ff%type = type_dftb

       ! calculate the maximum cutoff
       mcut = -1d0
       do i = 1, size(ff%bas)
          do j = 1, ff%bas(i)%norb
             mcut = max(mcut,ff%bas(i)%cutoff(j))
          end do
       end do

       ! register structural info
       do i = 1, cr%nenv
          renv0(:,i) = cr%atenv(i)%r
          lenv0(:,i) = cr%atenv(i)%lenv
          zenv0(i) = cr%at(cr%atenv(i)%idx)%z
          idx0(i) = cr%atenv(i)%cidx
       end do
       call dftb_register_struct(cr%crys2car,mcut,cr%nenv,renv0,lenv0,idx0,zenv0)

       ff%file = file
    else if (equal(wext1,'CHGCAR').or.equal(wext1,'AECCAR0').or.equal(wext1,'AECCAR2')) then
       call grid_read_vasp(file,ff,cr%omega)
       ff%type = type_grid
       ff%file = file
    else if (equal(wext1,'CHG') .or. equal(wext1,'ELFCAR')) then
       call grid_read_vasp(file,ff,1d0)
       ff%type = type_grid
       ff%file = file
    else if (equal(wext1,'qub')) then
       call grid_read_qub(file,ff)
       ff%type = type_grid
       ff%file = file
    else if (equal(wext1,'xsf')) then
       call grid_read_xsf(file,ff)
       ff%type = type_grid
       ff%file = file
    else if (equal(wext1,'wfn')) then
       call wfn_read_wfn(file,ff)
       ff%type = type_wfn
       call wfn_register_struct(cr%ncel,cr%atcel)
       ff%file = file
    else if (equal(wext1,'wfx')) then
       call wfn_read_wfx(file,ff)
       ff%type = type_wfn
       call wfn_register_struct(cr%ncel,cr%atcel)
       ff%file = file
    else if (equal(wext1,'fchk')) then
       call wfn_read_fchk(file,ff)
       ff%type = type_wfn
       call wfn_register_struct(cr%ncel,cr%atcel)
       ff%file = file
    else if (equal(wext1,'molden')) then
       call wfn_read_molden(file,ff)
       ff%type = type_wfn
       call wfn_register_struct(cr%ncel,cr%atcel)
       ff%file = file
    else if (equal(wext1,'clmsum')) then
       file2 = getword(line,lp)
       call wien_read_clmsum(file,file2,ff)
       ff%type = type_wien
       ff%file = file
    else if (equal(wext1,'OUT')) then
       file2 = ""
       file3 = ""

       lp2 = lp
       file2 = getword(line,lp)
       if (len_trim(file2) > 0) then
          word = file2(index(file2,dirsep,.true.)+1:)
          wext2 = word(index(word,'.',.true.)+1:)
          if (equal(wext2,'OUT')) then
             lp2 = lp
             file3 = getword(line,lp)
             if (len_trim(file3) > 0) then
                word = file3(index(file3,dirsep,.true.)+1:)
                wext2 = word(index(word,'.',.true.)+1:)
                if (.not.equal(wext2,'OUT')) then
                   file3 = ""
                   lp = lp2
                end if
             end if
          else
             file2 = ""
             lp = lp2
          end if
       end if

       if (file2 == "" .and. file3 == "") then
          call grid_read_elk(file,ff)
          ff%type = type_grid
          ff%file = file
       elseif (file3 == "") then
          call elk_read_out(ff,file,file2)
          ff%type = type_elk
          ff%file = file
       else
          call elk_read_out(ff,file,file2,file3)
          ff%type = type_elk
          ff%file = file3
       end if
    else if (equal(wext1,'promolecular')) then
       lp2 = lp
       word = lgetword(line,lp)
       if (equal(word,"fragment")) then
          word = getword(line,lp)
          fr = cr%identify_fragment_from_xyz(word)
          ff%type = type_promol_frag
          ff%fr = fr
       else
          lp = lp2
          ff%type = type_promol
       end if
       ff%init = .true.
    else if (equal(wext1,'ion')) then
       ! read all the ions
       ff%file = ""
       do while(.true.)
          lp2 = lp
          ok = eval_next(zz,line,lp)
          if (ok) then
             call pi_read_ion(file,ff,zz)
          else
             word = lgetword(line,lp2)
             zz = zatguess(word)
             if (zz == -1) then
                call ferror("fields_load_real","syntax: load file.ion {atidx/atsym} ...",faterr,line,syntax=.true.)
                return
             end if
             do i = 1, cr%nneq
                if (cr%at(i)%z == zz) call pi_read_ion(file,ff,i)
             end do
             ff%file = adjustl(trim(ff%file) // " " // file)
             lp = lp2
          endif
          lp2 = lp
          file = getword(line,lp)
          wext1 = file(index(file,'.',.true.)+1:)
          if (.not.equal(wext1,'ion')) then
             lp = lp2
             exit
          end if
       end do

       do i = 1, cr%nneq
          if (.not.ff%pi_used(i)) then
             call ferror("field_load","missing atoms in pi field description",faterr)
          end if
       end do
       ff%type = type_pi
       ff%init = .true.
       ff%exact = .false.
       ff%file = trim(ff%file)

       ! register structural info in the pi module
       do i = 1, cr%nenv
          renv0(:,i) = cr%atenv(i)%r
          idx0(i) = cr%atenv(i)%idx
          zenv0(i) = cr%at(cr%atenv(i)%idx)%z
       end do
       call pi_register_struct(cr%nenv,renv0,idx0,zenv0)

       ! fill the interpolation tables of the field
       call fillinterpol(ff)

    else if (equal(wext1,'chk')) then
       nou = .false.
       nochk = .false.
       wancut = -1d0
       nword = 0
       file2 = ""
       file3 = ""
       file4 = ""
       ff%wan%useu = .true.
       ff%wan%sijchk = .true.
       ff%wan%fachk = .true.
       ff%wan%haschk = .false.
       ff%wan%cutoff = -1d0
       do while (.true.)
          word = getword(line,lp)
          lword = lower(word)
          nword = nword + 1
          if (equal(lword,"nou")) then
             ff%wan%useu = .false.
          elseif (equal(lword,"nosijchk")) then
             ff%wan%sijchk = .false.
          elseif (equal(lword,"nofachk")) then
             ff%wan%fachk = .false.
          elseif (equal(lword,"wancut")) then
             ok = eval_next(ff%wan%cutoff,line,lp)
          elseif (equal(lword,"unkgen")) then
             file3 = getword(line,lp)
             file4 = getword(line,lp)
          else if (len_trim(lword) > 0) then
             if (nword == 1) then
                file2 = word
             else
                call ferror('fields_load_real','Unknown extra keyword',faterr,line,syntax=.true.)
                return
             end if
          else
             exit
          end if
       end do

       if (len_trim(file3) < 1) then
          call grid_read_unk(file,file2,ff,cr%omega,nou,ff%wan%sijchk)
       else
          call grid_read_unkgen(file,file2,file3,file4,ff,cr%omega,ff%wan%sijchk)
       end if
       ff%type = type_grid
       ff%file = trim(file)
       ff%init = .true.

    else if (equal(wext1,'as')) then
       lp2 = lp
       word = getword(line,lp)
       lword = lower(word)
       if (equal(lword,"promolecular").or.equal(lword,"core").or.&
           equal(lword,"grad").or.equal(lword,"lap").or.equal(lword,"taufromelf")) then
          ! load as {promolecular,core,grad,lap,taufromelf}

          if (equal(lword,"promolecular").or.equal(lword,"core")) then
             ok = eval_next(n(1),line,lp)
             if (ok) then
                ok = ok .and. eval_next(n(2),line,lp)
                ok = ok .and. eval_next(n(3),line,lp)
                if (.not.ok) then
                   call ferror("fields_load_real","wrong grid size for promolecular/core",faterr,line,syntax=.true.)
                   return
                end if
             else
                word2 = lgetword(line,lp)
                if (equal(word2,"sizeof")) then
                   word2 = getword(line,lp)
                   zz = fieldname_to_idx(word2)
                   if (zz < 0) then
                      call ferror("fields_load_real","wrong sizeof",faterr,line,syntax=.true.)
                      return
                   end if
                   if (.not.goodfield(zz,type_grid)) then
                      call ferror("fields_load_real","field not allocated",faterr,line,syntax=.true.)
                      return
                   end if
                   n = f(zz)%n
                else
                   call ferror("fields_load_real","wrong grid size",faterr,line,syntax=.true.)
                   return
                end if
             end if
          else
             word2 = getword(line,lp)
             oid = fieldname_to_idx(word2)
             if (oid < 0) then
                call ferror("fields_load_real","wrong grid for lap/grad/etc.",faterr,line,syntax=.true.)
                return
             end if
             if (.not.goodfield(oid)) then
                call ferror("fields_load_real","field not allocated",faterr,line,syntax=.true.)
                return
             end if
             n = f(oid)%n
          end if

          if (equal(lword,"promolecular").or.equal(lword,"core").or.goodfield(oid,type_grid)) then 
             isfrag = .false.
             if (equal(lword,"promolecular").or.equal(lword,"core")) then
                ! maybe we are given a fragment?
                lp2 = lp
                word2 = lgetword(line,lp)
                if (equal(word2,"fragment")) then
                   word2 = getword(line,lp)
                   isfrag = (len_trim(word2) > 0)
                   if (isfrag) fr = cr%identify_fragment_from_xyz(word2)
                else
                   lp = lp2
                   isfrag = .false.
                end if
             end if
             ! build a grid 
             ff%init = .true.
             ff%n = n
             ff%type = type_grid
             ff%mode = mode_tricubic
             ff%c2x = cr%car2crys
             ff%x2c = cr%crys2car
             allocate(ff%f(n(1),n(2),n(3)))
             if (equal(lword,"promolecular")) then
                if (isfrag) then
                   call grid_rhoat(ff,ff,2,fr)
                else
                   call grid_rhoat(ff,ff,2)
                end if
             elseif (equal(lword,"core")) then
                if (isfrag) then
                   call grid_rhoat(ff,ff,3,fr)
                else
                   call grid_rhoat(ff,ff,3)
                end if
             elseif (equal(lword,"lap")) then
                call grid_laplacian(f(oid),ff)
             elseif (equal(lword,"grad")) then
                call grid_gradrho(f(oid),ff)
             end if
          elseif ((goodfield(oid,type_wien).or.goodfield(oid,type_elk)).and.equal(lword,"lap")) then
             ! calculate the laplacian of a lapw scalar field
             ff = f(oid)
             if (f(oid)%type == type_wien) then
                call wien_tolap(ff)
             else
                call elk_tolap(ff)
             end if
          else
             call ferror("fields_load_real","Incorrect scalar field type",faterr,line,syntax=.true.)
             return
          endif

       elseif (equal(lword,"clm")) then
          ! load as clm
          word = lgetword(line,lp)
          if (equal(word,'add').or.equal(word,'sub')) then
             word2 = getword(line,lp)
             id1 = fieldname_to_idx(word2)
             word2 = getword(line,lp)
             id2 = fieldname_to_idx(word2)
             if (id1 < 0 .or. id2 < 0) then
                call ferror("fields_load_real","wrong syntax in LOAD AS CLM",faterr,line,syntax=.true.)
                return
             end if
             if (.not.goodfield(id1).or..not.goodfield(id2)) then
                call ferror("fields_load_real","field not allocated",faterr,line,syntax=.true.)
                return
             end if
             if (f(id1)%type/=f(id2)%type) then
                call ferror("fields_load_real","fields not the same type",faterr,line,syntax=.true.)
                return
             end if
             if (f(id1)%type/=type_wien.and.f(id1)%type/=type_elk) then
                call ferror("fields_load_real","incorrect type",faterr,line,syntax=.true.) 
                return
             end if
             if (f(id1)%type == type_wien) then
                ! wien
                ff = f(id1)
                if (any(shape(f(id1)%slm) /= shape(f(id2)%slm))) then
                   call ferror("fields_load_real","nonconformant slm in wien fields",faterr,line,syntax=.true.) 
                   return
                end if
                if (any(shape(f(id1)%sk) /= shape(f(id2)%sk))) then
                   call ferror("fields_load_real","nonconformant sk in wien fields",faterr,line,syntax=.true.) 
                   return
                end if
                if (equal(word,'add')) then
                   ff%slm = ff%slm + f(id2)%slm
                   ff%sk = ff%sk + f(id2)%sk
                   if (allocated(ff%ski)) &
                      ff%ski = ff%ski + f(id2)%ski
                else
                   ff%slm = ff%slm - f(id2)%slm
                   ff%sk = ff%sk - f(id2)%sk
                   if (allocated(ff%ski)) &
                      ff%ski = ff%ski - f(id2)%ski
                end if
             else
                ! elk
                ff = f(id1)
                if (any(shape(f(id1)%rhomt) /= shape(f(id2)%rhomt))) then
                   call ferror("fields_load_real","nonconformant rhomt in elk fields",faterr,line,syntax=.true.) 
                   return
                end if
                if (any(shape(f(id1)%rhok) /= shape(f(id2)%rhok))) then
                   call ferror("fields_load_real","nonconformant rhok in elk fields",faterr,line,syntax=.true.) 
                   return
                end if
                if (equal(word,'add')) then
                   ff%rhomt = ff%rhomt + f(id2)%rhomt
                   ff%rhok = ff%rhok + f(id2)%rhok
                else
                   ff%rhomt = ff%rhomt - f(id2)%rhomt
                   ff%rhok = ff%rhok - f(id2)%rhok
                end if
             end if
          else
             call ferror("fields_load_real","invalid CLM syntax",faterr,line,syntax=.true.)
             return
          end if
       elseif (isexpression_or_word(expr,line,lp2)) then
          ! load as "blehblah"
          lp = lp2
          ok = eval_next(n(1),line,lp)
          if (ok) then
             ! load as "blehblah" n1 n2 n3 
             ok = ok .and. eval_next(n(2),line,lp)
             ok = ok .and. eval_next(n(3),line,lp)
          else
             lp2 = lp
             word2 = lgetword(line,lp)
             if (equal(word2,"sizeof")) then
                ! load as "blehblah" sizeof
                word2 = getword(line,lp)
                zz = fieldname_to_idx(word2)
                if (zz < 0) then
                   call ferror("fields_load_real","wrong sizeof",faterr,line,syntax=.true.)
                   return
                end if
                if (.not.goodfield(zz,type_grid)) then
                   call ferror("fields_load_real","field not allocated",faterr,line,syntax=.true.)
                   return
                end if
                n = f(zz)%n
             elseif (equal(word2,"ghost")) then
                ! load as "blehblah" ghost
                ! ghost field -> no grid size
                n = 0
                call fields_in_eval(expr,nid,idlist)
             else
                ! load as "blehblah"
                lp = lp2
                call fields_in_eval(expr,nid,idlist)
                n = 0
                do i = 1, nid
                   id = fieldname_to_idx(idlist(i))
                   if (.not.goodfield(id,type_grid)) cycle
                   do j = 1, 3
                      n(j) = max(n(j),f(id)%n(j))
                   end do
                end do
                if (any(n < 1)) then
                   ! nothing read, must be a ghost
                   call fields_in_eval(expr,nid,idlist)
                endif
             end if
          end if

          if (any(n < 1)) then
             ! Ghost field
             do i = 1, nid
                id = fieldname_to_idx(idlist(i))
                if (id < 0) then
                   call ferror('fields_load_real','Tried to define ghost field using and undefined field',faterr,syntax=.true.)
                   return
                end if
                if (.not.fused(id)) then
                   call ferror('fields_load_real','Tried to define ghost field using and undefined field',faterr,syntax=.true.)
                   return
                end if
             end do

             ff%init = .true.
             ff%type = type_ghost
             ff%expr = string(expr)
             ff%nf = nid
             if (allocated(ff%fused)) deallocate(ff%fused)
             allocate(ff%fused(nid))
             do i = 1, nid
                ff%fused(i) = fieldname_to_idx(idlist(i))
             end do
             ff%usecore = .false.
             ff%numerical = .true.
          else
             ! Grid field
             ! prepare the cube
             ff%init = .true.
             ff%n = n
             ff%type = type_grid
             ff%mode = mode_tricubic
             allocate(ff%f(n(1),n(2),n(3)))

             ! dimensions
             xd = eye
             do i = 1, 3
                xd(:,i) = cr%x2c(xd(:,i))
                xd(:,i) = xd(:,i) / real(n(i),8)
             end do

             ! check that the evaluation works
             xp = 0d0
             rhopt = eval(expr,.false.,iok,xp,fields_fcheck,fields_feval)
             if (.not.iok) then
                call ferror('fields_load_real','Error evaluationg expression: ' // string(expr),faterr,syntax=.true.)
                return
             end if

             !$omp parallel do private (xp,rhopt) schedule(dynamic)
             do ix = 0, n(1)-1
                do iy = 0, n(2)-1
                   do iz = 0, n(3)-1
                      xp = real(ix,8) * xd(:,1) + real(iy,8) * xd(:,2) &
                         + real(iz,8) * xd(:,3)
                      rhopt = eval(expr,.true.,iok,xp,fields_fcheck,fields_feval)
                      !$omp critical (fieldwrite)
                      ff%f(ix+1,iy+1,iz+1) = rhopt
                      !$omp end critical (fieldwrite)
                   end do
                end do
             end do
             !$omp end parallel do
          end if
       else
          call ferror("fields_load_real","invalid AS syntax",faterr,line,syntax=.true.)
          return
       end if
    else
       call ferror('fields_load_real','unrecognized file format',faterr,line,syntax=.true.)
       return
    end if

    ! fill misc values
    ff%c2x = cr%car2crys
    ff%x2c = cr%crys2car
    ff%typnuc = -3

    ! use cores?
    ff%usecore = .false.

    ! parse the rest of the line
    call setfield(ff,fid,line(lp:),oksyn,dormt)
    if (.not.oksyn) return

    oksyn = .true.

  end function fields_load_real

  !> Unload the field in slot id.
  subroutine fields_unload(id)
    use tools_io, only: string
    use param, only: fh

    integer, intent(in) :: id

    integer :: i, idum, nkeys
    character(len=:), allocatable :: key

    fused(id) = .false.
    if (fh%iskey(string(id))) call fh%delkey(string(id))
    f(id)%init = .false.
    f(id)%iswan = .false.
    f(id)%name = ""
    f(id)%file = ""
    if (allocated(f(id)%f)) deallocate(f(id)%f)
    if (allocated(f(id)%c2)) deallocate(f(id)%c2)
    if (allocated(f(id)%wan%kpt)) deallocate(f(id)%wan%kpt)
    if (allocated(f(id)%wan%center)) deallocate(f(id)%wan%center)
    if (allocated(f(id)%wan%spread)) deallocate(f(id)%wan%spread)
    if (allocated(f(id)%wan%ngk)) deallocate(f(id)%wan%ngk)
    if (allocated(f(id)%wan%igk_k)) deallocate(f(id)%wan%igk_k)
    if (allocated(f(id)%wan%nls)) deallocate(f(id)%wan%nls)
    if (allocated(f(id)%wan%u)) deallocate(f(id)%wan%u)
    if (allocated(f(id)%lm)) deallocate(f(id)%lm)
    if (allocated(f(id)%lmmax)) deallocate(f(id)%lmmax)
    if (allocated(f(id)%slm)) deallocate(f(id)%slm)
    if (allocated(f(id)%sk)) deallocate(f(id)%sk)
    if (allocated(f(id)%ski)) deallocate(f(id)%ski)
    if (allocated(f(id)%tauk)) deallocate(f(id)%tauk)
    if (allocated(f(id)%tauki)) deallocate(f(id)%tauki)
    if (allocated(f(id)%rotloc)) deallocate(f(id)%rotloc)
    if (allocated(f(id)%rnot)) deallocate(f(id)%rnot)
    if (allocated(f(id)%rmt)) deallocate(f(id)%rmt)
    if (allocated(f(id)%dx)) deallocate(f(id)%dx)
    if (allocated(f(id)%jri)) deallocate(f(id)%jri)
    if (allocated(f(id)%multw)) deallocate(f(id)%multw)
    if (allocated(f(id)%iatnr)) deallocate(f(id)%iatnr)
    if (allocated(f(id)%pos)) deallocate(f(id)%pos)
    if (allocated(f(id)%iop)) deallocate(f(id)%iop)
    if (allocated(f(id)%iz)) deallocate(f(id)%iz)
    if (allocated(f(id)%tau)) deallocate(f(id)%tau)
    if (allocated(f(id)%krec)) deallocate(f(id)%krec)
    if (allocated(f(id)%inst)) deallocate(f(id)%inst)
    if (allocated(f(id)%rhomt)) deallocate(f(id)%rhomt)
    if (allocated(f(id)%rhok)) deallocate(f(id)%rhok)
    if (allocated(f(id)%spr)) deallocate(f(id)%spr)
    if (allocated(f(id)%spr_a)) deallocate(f(id)%spr_a)
    if (allocated(f(id)%spr_b)) deallocate(f(id)%spr_b)
    if (allocated(f(id)%nrmt)) deallocate(f(id)%nrmt)
    if (allocated(f(id)%vgc)) deallocate(f(id)%vgc)
    if (allocated(f(id)%igfft)) deallocate(f(id)%igfft)
    if (allocated(f(id)%xcel)) deallocate(f(id)%xcel)
    if (allocated(f(id)%iesp)) deallocate(f(id)%iesp)
    if (allocated(f(id)%piname)) deallocate(f(id)%piname)
    if (allocated(f(id)%pi_used)) deallocate(f(id)%pi_used)
    if (allocated(f(id)%nsym)) deallocate(f(id)%nsym)
    if (allocated(f(id)%naos)) deallocate(f(id)%naos)
    if (allocated(f(id)%naaos)) deallocate(f(id)%naaos)
    if (allocated(f(id)%nsto)) deallocate(f(id)%nsto)
    if (allocated(f(id)%nasto)) deallocate(f(id)%nasto)
    if (allocated(f(id)%nn)) deallocate(f(id)%nn)
    if (allocated(f(id)%z)) deallocate(f(id)%z)
    if (allocated(f(id)%xnsto)) deallocate(f(id)%xnsto)
    if (allocated(f(id)%c)) deallocate(f(id)%c)
    if (allocated(f(id)%nelec)) deallocate(f(id)%nelec)
    if (allocated(f(id)%pgrid)) deallocate(f(id)%pgrid)
    if (allocated(f(id)%icenter)) deallocate(f(id)%icenter)
    if (allocated(f(id)%itype)) deallocate(f(id)%itype)
    if (allocated(f(id)%d2ran)) deallocate(f(id)%d2ran)
    if (allocated(f(id)%e)) deallocate(f(id)%e)
    if (allocated(f(id)%occ)) deallocate(f(id)%occ)
    if (allocated(f(id)%cmo)) deallocate(f(id)%cmo)
    if (allocated(f(id)%icenter_edf)) deallocate(f(id)%icenter_edf)
    if (allocated(f(id)%itype_edf)) deallocate(f(id)%itype_edf)
    if (allocated(f(id)%e_edf)) deallocate(f(id)%itype_edf)
    if (allocated(f(id)%c_edf)) deallocate(f(id)%c_edf)
    if (allocated(f(id)%docc)) deallocate(f(id)%docc)
    if (allocated(f(id)%dkpt)) deallocate(f(id)%dkpt)
    if (allocated(f(id)%evecr)) deallocate(f(id)%evecr)
    if (allocated(f(id)%evecc)) deallocate(f(id)%evecc)
    if (allocated(f(id)%ispec)) deallocate(f(id)%ispec)
    if (allocated(f(id)%idxorb)) deallocate(f(id)%idxorb)
    if (allocated(f(id)%bas)) deallocate(f(id)%bas)
    if (allocated(f(id)%fused)) deallocate(f(id)%fused)

    ! clear all alias referring to this field
    nkeys = fh%keys()
    do i = 1, nkeys
       key = fh%getkey(i)
       idum = fh%get(key,idum)
       if (idum == id) call fh%delkey(key)
    end do

  end subroutine fields_unload

  !> Calculates the properties of the scalar field f at point x0 and fills the
  !> blanks.
  subroutine fields_propty(id,x0,res,verbose,allfields)
    use crystalmod, only: cr
    use global, only: cp_hdegen
    use tools_math, only: rsindex
    use tools_io, only: uout, string
    use arithmetic, only: eval
    use types, only: scalar_value

    integer, intent(in) :: id
    real*8, dimension(:), intent(in)  :: x0
    type(scalar_value), intent(out) :: res
    logical, intent(in) :: verbose, allfields

    real*8 :: xp(3), fres, stvec(3,3), stval(3)
    integer :: str, sts
    integer :: i, j, k
    logical :: iok
    type(scalar_value) :: res2

    ! get the scalar field properties
    xp = cr%x2c(x0)
    call grd(f(id),xp,2,res0=res)

    ! r and s
    res%hfevec = res%hf
    call rsindex(res%hfevec,res%hfeval,res%r,res%s,CP_hdegen)

    if (verbose) then
       if (res%isnuc) then
          write (uout,'("  Type : nucleus")') 
       else
          write (uout,'("  Type : (",a,",",a,")")') string(res%r), string(res%s)
       end if
       write (uout,'("  Field value (f): ",A)') string(res%f,'e',decimal=9)
       write (uout,'("  Field value, valence (fval): ",A)') string(res%fval,'e',decimal=9)
       write (uout,'("  Gradient (grad f): ",3(A,2X))') (string(res%gf(j),'e',decimal=9),j=1,3)
       write (uout,'("  Gradient norm (|grad f|): ",A)') string(res%gfmod,'e',decimal=9)
       write (uout,'("  Laplacian (del2 f): ",A)') string(res%del2f,'e',decimal=9)
       write (uout,'("  Laplacian, valence (del2 fval): ",A)') string(res%del2fval,'e',decimal=9)
       write (uout,'("  Hessian:")')
       do j = 1, 3
          write (uout,'(4x,1p,3(A,2X))') (string(res%hf(j,k),'e',decimal=9,length=16,justify=4), k = 1, 3)
       end do
       write (uout,'("  Hessian eigenvalues: ",3(A,2X))') (string(res%hfeval(j),'e',decimal=9),j=1,3)
       ! Write ellipticity, if it is a candidate for bond critical point
       if (res%r == 3 .and. res%s == -1 .and..not.res%isnuc) then
          write (uout,'("  Ellipticity (l_1/l_2 - 1): ",A)') string(res%hfeval(1)/res%hfeval(2)-1.d0,'e',decimal=9)
       endif
       if (allfields) then
          do i = 0, ubound(f,1)
             if (fused(i) .and. i /= id) then
                call grd(f(i),xp,2,res0=res2)
                write (uout,'("  Field ",A," (f,|grad|,lap): ",3(A,2X))') string(i),&
                   string(res2%f,'e',decimal=9), string(res2%gfmod,'e',decimal=9), &
                   string(res2%del2f,'e',decimal=9)
             end if
          end do
       end if

       ! properties at points defined by the user
       do i = 1, nptprops
          if (point_prop(i)%ispecial == 0) then
             ! ispecial=0 ... use the expression
             fres = eval(point_prop(i)%expr,.true.,iok,xp,fields_fcheck,fields_feval)
             write (uout,'(2X,A," (",A,"): ",A)') string(point_prop(i)%name),&
                string(point_prop(i)%expr), string(fres,'e',decimal=9)
          else
             ! ispecial=1 ... schrodinger stress tensor
             stvec = res%stress
             call rsindex(stvec,stval,str,sts,CP_hdegen)
             write (uout,'("  Stress tensor:")')
             do j = 1, 3
                write (uout,'(4x,1p,3(A,2X))') (string(res%stress(j,k),'e',decimal=9,length=16,justify=4), k = 1, 3)
             end do
             write (uout,'("  Stress tensor eigenvalues: ",3(A,2X))') (string(stval(j),'e',decimal=9),j=1,3)
          endif
       end do
    end if

  end subroutine fields_propty

  !> Define fields as integrable. Atomic integrals for these fields
  !> will be calculated in the basins of the reference field.
  subroutine fields_integrable(line)
    use global, only: refden, eval_next
    use tools_io, only: ferror, faterr, getword, lgetword, equal,&
       isexpression_or_word, string, isinteger, getline
    use types, only: realloc
    character*(*), intent(in) :: line

    logical :: ok
    integer :: id, lp, lpold, idum
    character(len=:), allocatable :: word, expr, str
    logical :: useexpr

    ! read input
    lp=1
    useexpr = .false.

    lpold = lp
    word = getword(line,lp)
    id = fieldname_to_idx(word)
    if (id < 0) then
       lp = lpold
       ! clear the integrable properties list
       word = lgetword(line,lp)
       if (equal(word,'clear')) then
          nprops = 3
          integ_prop(:)%used = .false.
          integ_prop(1)%used = .true.
          integ_prop(1)%itype = itype_v
          integ_prop(1)%fid = 0
          integ_prop(1)%prop_name = "Volume"
          integ_prop(2)%used = .true.
          integ_prop(2)%itype = itype_fval
          integ_prop(2)%fid = refden
          integ_prop(2)%prop_name = "Pop"
          integ_prop(3)%used = .true.
          integ_prop(3)%itype = itype_lapval
          integ_prop(3)%fid = refden
          integ_prop(3)%prop_name = "Lap"
          call fields_integrable_report()
          return
       else 
          lp = lpold
          if (isexpression_or_word(expr,line,lp)) then
             useexpr = .true.
          else
             call ferror("fields_integrable","Unknown integrable syntax",faterr,line,syntax=.true.)
             return
          endif
       end if
    else
       if (.not.goodfield(id)) then
          call ferror('fields_integrable','field not allocated',faterr,line,syntax=.true.)
          return
       end if
       str = "$" // string(word)
    end if

    ! add property
    nprops = nprops + 1
    if (nprops > size(integ_prop)) &
       call realloc(integ_prop,2*nprops)
    if (useexpr) then
       integ_prop(nprops)%used = .true.
       integ_prop(nprops)%fid = 0
       integ_prop(nprops)%itype = itype_expr
       integ_prop(nprops)%prop_name = trim(adjustl(expr))
       integ_prop(nprops)%expr = expr
    else
       integ_prop(nprops)%used = .true.
       integ_prop(nprops)%fid = id
       integ_prop(nprops)%itype = itype_f
       integ_prop(nprops)%prop_name = ""
       integ_prop(nprops)%lmax = 5
       do while (.true.)
          word = lgetword(line,lp)
          if (equal(word,"f")) then
             integ_prop(nprops)%itype = itype_f
             str = trim(str) // "#f"
          elseif (equal(word,"fval")) then
             integ_prop(nprops)%itype = itype_fval
             str = trim(str) // "#fval"
          elseif (equal(word,"gmod")) then
             integ_prop(nprops)%itype = itype_gmod
             str = trim(str) // "#gmod"
          elseif (equal(word,"lap")) then
             integ_prop(nprops)%itype = itype_lap
             str = trim(str) // "#lap"
          elseif (equal(word,"lapval")) then
             integ_prop(nprops)%itype = itype_lapval
             str = trim(str) // "#lapval"
          elseif (equal(word,"multipoles") .or. equal(word,"multipole")) then
             integ_prop(nprops)%itype = itype_mpoles
             str = trim(str) // "#mpol"
             ok = isinteger(idum,line,lp)
             if (ok) integ_prop(nprops)%lmax = idum
          elseif (equal(word,"deloc")) then
             integ_prop(nprops)%itype = itype_deloc
             str = trim(str) // "#deloca"
          elseif (equal(word,"deloc")) then
             integ_prop(nprops)%itype = itype_deloc
             str = trim(str) // "#deloca"
          elseif (equal(word,"name")) then
             word = getword(line,lp)
             integ_prop(nprops)%prop_name = string(word)
          else if (len_trim(word) > 0) then
             call ferror("fields_integrable","Unknown extra keyword",faterr,line,syntax=.true.)
             nprops = nprops - 1
             return
          else
             exit
          end if
       end do
       if (trim(integ_prop(nprops)%prop_name) == "") then
          integ_prop(nprops)%prop_name = str
       end if
    end if

    ! report
    call fields_integrable_report()

  end subroutine fields_integrable

  !> Report for the integrable fields.
  subroutine fields_integrable_report()
    use tools_io, only: ferror, faterr, string, ioj_center, ioj_right, uout

    integer :: i, id
    character*4 :: sprop

    write (uout,'("* List of integrable properties")')
    write (uout,'("# ",4(A,2X))') &
       string("Id",length=3,justify=ioj_right), string("Type",length=4,justify=ioj_center), &
       string("Field",length=5,justify=ioj_right), string("Name")
    do i = 1, nprops
       if (.not.integ_prop(i)%used) cycle
       id = integ_prop(i)%fid
       if (.not.goodfield(id)) cycle

       select case(integ_prop(i)%itype)
       case(itype_v)
          sprop = "v"
       case(itype_f)
          sprop = "f"
       case(itype_fval)
          sprop = "fval"
       case(itype_gmod)
          sprop = "gmod"
       case(itype_lap)
          sprop = "lap"
       case(itype_lapval)
          sprop = "lval"
       case(itype_expr)
          sprop = "expr"
       case(itype_mpoles)
          sprop = "mpol"
       case(itype_deloc)
          sprop = "dloc"
       case default
          call ferror('grdall','unknown property',faterr)
       end select

       if (integ_prop(i)%itype == itype_expr) then
          write (uout,'(2X,2(A,2X),2X,"""",A,"""")') &
             string(i,length=3,justify=ioj_right), string(sprop,length=4,justify=ioj_center), &
             string(integ_prop(i)%expr)
       else
          write (uout,'(2X,4(A,2X))') &
             string(i,length=3,justify=ioj_right), string(sprop,length=4,justify=ioj_center), &
             string(integ_prop(i)%fid,length=5,justify=ioj_right), string(integ_prop(i)%prop_name)
       end if
    end do
    write (uout,*)

  end subroutine fields_integrable_report

  !> Define properties to calculate at selected points in the unit cell. 
  subroutine fields_pointprop(line0)
    use global, only: refden
    use tools_io, only: ferror, faterr, uout, getword, lower, equal, string
    use arithmetic, only: fields_in_eval
    use types, only: realloc

    character*(*), intent(in) :: line0

    logical :: isblank, isstress
    integer :: lp, n, i
    character(len=:), allocatable :: expr, word, lword, line
    character*255, allocatable :: idlist(:)

    ! Get the name
    lp = 1
    line = line0
    word = getword(line,lp)
    isstress = .false.
    lword = lower(word)
    if (equal(lword,'clear')) then
       do i = 1, nptprops
          point_prop(i)%name = ""
          point_prop(i)%expr = ""
          point_prop(i)%nf = 0
          point_prop(i)%ispecial = 0
          if (allocated(point_prop(i)%fused)) deallocate(point_prop(i)%fused)
       end do
       nptprops = 0
       write(uout,'("* No properties to be calculated at points (POINTPROP)"/)')
       return
    elseif (equal(lword,'gtf')) then
       lp = 1 
       line = "gtf(" // string(refden) // ")"
    elseif (equal(lword,'vtf')) then
       lp = 1 
       line = "vtf(" // string(refden) // ")"
    elseif (equal(lword,'htf')) then
       lp = 1 
       line = "htf(" // string(refden) // ")"
    elseif (equal(lword,'gtf_kir')) then
       lp = 1 
       line = "gtf_kir(" // string(refden) // ")"
    elseif (equal(lword,'vtf_kir')) then
       lp = 1 
       line = "vtf_kir(" // string(refden) // ")"
    elseif (equal(lword,'htf_kir')) then
       lp = 1 
       line = "htf_kir(" // string(refden) // ")"
    elseif (equal(lword,'gkin')) then
       lp = 1 
       line = "gkin(" // string(refden) // ")"
    elseif (equal(lword,'kkin')) then
       lp = 1 
       line = "kkin(" // string(refden) // ")"
    elseif (equal(lword,'lag')) then
       lp = 1 
       line = "lag(" // string(refden) // ")"
    elseif (equal(lword,'elf')) then
       lp = 1 
       line = "elf(" // string(refden) // ")"
    elseif (equal(lword,'stress')) then
       lp = 1
       line = "stress(" // string(refden) // ")"
       isstress = .true.
    elseif (equal(lword,'vir')) then
       lp = 1 
       line = "vir(" // string(refden) // ")"
    elseif (equal(lword,'he')) then
       lp = 1 
       line = "he(" // string(refden) // ")"
    elseif (equal(lword,'lol')) then
       lp = 1 
       line = "lol(" // string(refden) // ")"
    elseif (equal(lword,'lol_kir')) then
       lp = 1 
       line = "lol_kir(" // string(refden) // ")"
    elseif (len_trim(lword) == 0) then
       call fields_pointprop_report()
       return
    endif

    ! Clean up the string
    expr = ""
    isblank = .false.
    do i = lp, len_trim(line)
       if (line(i:i) == " ") then
          if (.not.isblank) then
             expr = expr // line(i:i)
             isblank = .true.
          end if
       elseif (line(i:i) /= """" .and. line(i:i) /= "'") then
          expr = expr // line(i:i)
          isblank = .false.
       endif
    end do
    expr = trim(adjustl(expr))
    if (len_trim(expr) == 0) then
       call ferror("fields_pointprop","Wrong arithmetic expression",faterr,line,syntax=.true.)
       return
    end if

    ! Add this pointprop to the list
    nptprops = nptprops + 1
    if (nptprops > size(point_prop)) &
       call realloc(point_prop,2*nptprops)
    point_prop(nptprops)%name = word
    point_prop(nptprops)%expr = expr
    if (isstress) then
       point_prop(nptprops)%ispecial = 1
    else
       point_prop(nptprops)%ispecial = 0
    end if

    ! Determine the fields in the expression, check that they are defined
    if (point_prop(nptprops)%ispecial == 0) then
       call fields_in_eval(expr,n,idlist)
       do i = 1, n
          if (.not.goodfield(fieldname_to_idx(idlist(i)))) then
             call ferror("fields_pointprop","Unknown field in arithmetic expression",faterr,expr,syntax=.true.)
             nptprops = nptprops - 1
             return
          end if
       end do

       ! fill the fused array
       if (allocated(point_prop(nptprops)%fused)) deallocate(point_prop(nptprops)%fused)
       allocate(point_prop(nptprops)%fused(n))
       point_prop(nptprops)%nf = n
       do i = 1, n
          point_prop(nptprops)%fused(i) = fieldname_to_idx(idlist(i))
       end do
    else
       if (allocated(point_prop(nptprops)%fused)) deallocate(point_prop(nptprops)%fused)
       allocate(point_prop(nptprops)%fused(1))
       point_prop(nptprops)%nf = 1
       point_prop(nptprops)%fused(1) = refden
    end if

    ! Print report
    call fields_pointprop_report()

    ! Clean up
    if (allocated(idlist)) deallocate(idlist)

  end subroutine fields_pointprop

  !> Report for the pointprop fields.
  subroutine fields_pointprop_report()
    use tools_io, only: uout, string, ioj_center, ioj_right
  
    integer :: i
  
    write(uout,'("* List of properties to be calculated at (critical) points (POINTPROP)")')
    write(uout,'("# Id      Name       Expression")')
    do i = 1, nptprops
       write (uout,'(2X,2(A,2X),2X,"""",A,"""")') &
          string(i,length=3,justify=ioj_right), &
          string(point_prop(i)%name,length=10,justify=ioj_center), &
          string(point_prop(i)%expr)
    end do
    write (uout,*)
  
  end subroutine fields_pointprop_report

  !> List all defined aliases for fields
  subroutine listfields()
    use tools_io, only: ioj_right, uout, string
    integer :: i, n
    character(len=:), allocatable :: name, file, type

    n = count(fused)
    write (uout,'("* LIST of fields (",A,")")') string(n)
    do i = 0, ubound(fused,1)
       if (fused(i)) then
          name = trim(f(i)%name)
          if (len_trim(name) == 0) name = "<unnamed>"
          file = trim(f(i)%file)
          if (len_trim(file) == 0) file = "<no-file>"
          type = trim(fields_typestring(f(i)%type))
          write (uout,'(A,". ",A,", ",A,", ",A)') string(i,3,ioj_right), &
             string(type), string(name), string(file)
       end if
    end do
    write (uout,*)

  end subroutine listfields

  !> List all defined aliases for fields
  subroutine listfieldalias()
    use tools_io, only: uout, string
    use param, only: fh

    integer :: i, nkeys, idum
    character(len=:), allocatable :: key, val

    nkeys = fh%keys()
    write (uout,'("* LIST of named fields (",A,")")') string(nkeys)
    do i = 1, nkeys
       key = fh%getkey(i)
       val = string(fh%get(key,idum))
       write (uout,'(2X,"''",A,"'' is field number ",A)') string(key), string(val)
    end do
    write (uout,*)

  end subroutine listfieldalias

  !> Write a grid to a cube file. The input is the crystal (c),
  !> the grid in 3D array form (g), the filename (file), and whether
  !> to write the whole cube or only the header (onlyheader). If xd0
  !> is given, use it as the metric of the cube; otherwise, use the
  !> unit cell. If x00 is given, use it as the origin of the cube
  !> (in bohr). Otherwise, use the crystal's molx0.
  subroutine writegrid_cube(c,g,file,onlyheader,xd0,x00)
    use crystalmod, only: crystal
    use global, only: precisecube
    use tools_io, only: fopen_write, fclose
    use param, only: eye
    type(crystal), intent(in) :: c
    real*8, intent(in) :: g(:,:,:)
    character*(*), intent(in) :: file
    logical, intent(in) :: onlyheader
    real*8, intent(in), optional :: xd0(3,3)
    real*8, intent(in), optional :: x00(3)

    integer :: n(3), i, ix, iy, iz, lu
    real*8 :: xd(3,3), x0(3)

    do i = 1, 3
       n(i) = size(g,i)
    end do
    if (present(xd0)) then
       xd = xd0
    else
       xd = eye
       do i = 1, 3
          xd(:,i) = c%x2c(xd(:,i))
          xd(:,i) = xd(:,i) / real(n(i),8)
       end do
    endif
    if (present(x00)) then
       x0 = x00
    else
       x0 = c%molx0
    endif

    lu = fopen_write(file)
    write(lu,'("critic2-cube")')
    write(lu,'("critic2-cube")')
    if (precisecube) then
       write(lu,'(I5,1x,3(E22.14,1X))') c%ncel, x0
       do i = 1, 3
          write(lu,'(I5,1x,3(E22.14,1X))') n(i), xd(:,i)
       end do
       do i = 1, c%ncel
          write(lu,'(I4,F5.1,3(E22.14,1X))') c%at(c%atcel(i)%idx)%z, 0d0, c%atcel(i)%r(:) + c%molx0
       end do
    else
       write(lu,'(I5,3(F12.6))') c%ncel, x0
       do i = 1, 3
          write(lu,'(I5,3(F12.6))') n(i), xd(:,i)
       end do
       do i = 1, c%ncel
          write(lu,'(I4,F5.1,F11.6,F11.6,F11.6)') c%at(c%atcel(i)%idx)%z, 0d0, c%atcel(i)%r(:) + c%molx0
       end do
    end if
    if (.not.onlyheader) then
       do ix = 1, n(1)
          do iy = 1, n(2)
             if (precisecube) then
                write (lu,'(6(1x,e22.14))') (g(ix,iy,iz),iz=1,n(3))
             else
                write (lu,'(1p,6(1x,e12.5))') (g(ix,iy,iz),iz=1,n(3))
             end if
          enddo
       enddo
    end if
    call fclose(lu)

  end subroutine writegrid_cube

  !> Write a grid to a VASP CHGCAR file. The input is the crystal (c),
  !> the grid in 3D array form (g), the filename (file), and whether
  !> to write the whole cube or only the header (onlyheader). 
  subroutine writegrid_vasp(c,g,file,onlyheader)
    use crystalmod, only: crystal
    use tools_io, only: fopen_write, string, nameguess, fclose
    use param, only: bohrtoa, maxzat0

    type(crystal), intent(in) :: c
    real*8, intent(in) :: g(:,:,:)
    character*(*), intent(in) :: file
    logical :: onlyheader

    integer :: n(3), i, j, ix, iy, iz, lu
    integer :: ntyp(maxzat0)
    character(len=:), allocatable :: line0

    do i = 1, 3
       n(i) = size(g,i)
    end do

    lu = fopen_write(file)
    write (lu,'("CHGCAR generated by critic2")')
    write (lu,'("1.0")')
    do i = 1, 3
       write (lu,'(1p,3(E22.14,X))') c%crys2car(:,i) * bohrtoa
    end do
    ! count number of atoms per type
    ntyp = 0
    do i = 1, c%ncel
       ntyp(c%at(c%atcel(i)%idx)%z) = ntyp(c%at(c%atcel(i)%idx)%z) + 1
    end do
    line0 = ""
    do i = 1, maxzat0
       if (ntyp(i) > 0) then
          line0 = line0 // " " // string(nameguess(i,.true.))
       end if
    end do
    write (lu,'(A)') line0
    line0 = ""
    do i = 1, maxzat0
       if (ntyp(i) > 0) then
          line0 = line0 // " " // string(ntyp(i))
       end if
    end do
    write (lu,'(A)') line0
    write (lu,'("Direct")')
    do i = 1, maxzat0
       if (ntyp(i) > 0) then
          do j = 1, c%ncel
             if (c%at(c%atcel(j)%idx)%z /= i) cycle
             write (lu,'(1p,3(E22.14,X))') c%atcel(j)%x
          end do
       end if
    end do
    write (lu,*)
    write (lu,'(3(I5,X))') n
    if (.not.onlyheader) then
       write (lu,'(5(1x,e22.14))') (((g(ix,iy,iz)*c%omega,ix=1,n(1)),iy=1,n(2)),iz=1,n(3))
    end if
    call fclose(lu)

  end subroutine writegrid_vasp

  !> Returns .true. if the field is initialized and usable.
  logical function goodfield(id,type) result(good)
    integer, intent(in) :: id
    integer, intent(in), optional :: type

    good = (id >= 0 .and. id <= ubound(f,1))
    if (.not.good) return
    good = fused(id)
    if (.not.good) return
    good = f(id)%init
    if (.not.good) return
    if (present(type)) then
       good = (f(id)%type == type)
       if (.not.good) return
    end if

  end function goodfield

  !> Gives an unused field number
  integer function getfieldnum() result(id)
    use tools_io, only: string
    use types, only: realloc
    use param, only: fh

    integer :: mf
    logical :: found

    found = .false.
    do id = 1, ubound(f,1)
       if (.not.fused(id)) then
          found = .true.
          exit
       end if
    end do
    if (.not.found) then
       mf = ubound(f,1)
       call realloc(fused,mf+1)
       call realloc(f,mf+1)
       id = mf + 1
    end if
    fused(id) = .true.
    call fh%put(string(id),id)
    
  end function getfieldnum

  !> Set field flags. ff is the input/output field. fid is the intended
  !> slot. line is the input line to parse. oksyn is true in output if 
  !> the syntax was OK. dormt is true in output if the MT test
  !> discontinuity test needs to be run for elk/wien2k fields.
  subroutine setfield(ff,fid,line,oksyn,dormt)
    use crystalmod, only: cr
    use grid_tools, only: mode_nearest, mode_tricubic, mode_trilinear, mode_trispline
    use global, only: eval_next
    use tools_io, only: faterr, ferror, string, lgetword, equal, &
       isexpression_or_word
    use types, only: field
    use param, only: sqfp, fh

    type(field), intent(inout) :: ff
    integer, intent(in) :: fid
    character*(*), intent(in) :: line
    logical, intent(out) :: oksyn
    logical, intent(out), optional :: dormt

    character(len=:), allocatable :: word, aux
    integer :: lp
    logical :: ok
    real*8 :: norm

    ! default -> do the mt test
    if (present(dormt)) dormt = .true.

    ! parse the rest of the line
    oksyn = .false.
    lp = 1
    do while (.true.)
       word = lgetword(line,lp)
       if (equal(word,'tricubic')) then
          ff%mode = mode_tricubic
       else if (equal(word,'trispline')) then
          ff%mode = mode_trispline
          if (allocated(ff%c2)) deallocate(ff%c2)
       else if (equal(word,'trilinear')) then
          ff%mode = mode_trilinear
       else if (equal(word,'nearest')) then
          ff%mode = mode_nearest
       else if (equal(word,'exact')) then
          ff%exact = .true.
       else if (equal(word,'approximate')) then
          ff%exact = .false.
       else if (equal(word,'rhonorm')) then
          if (.not.ff%cnorm) then
             ff%cnorm = .true.
             if (allocated(ff%slm)) &
                ff%slm(:,1,:) = ff%slm(:,1,:) / sqfp
          end if
       else if (equal(word,'vnorm')) then
          if (ff%cnorm) then
             ff%cnorm = .false.
             if (allocated(ff%slm)) &
                ff%slm(:,1,:) = ff%slm(:,1,:) * sqfp
          end if
       else if (equal(word,'core')) then
          ff%usecore = .true.
       else if (equal(word,'nocore')) then
          ff%usecore = .false.
       else if (equal(word,'numerical')) then
          ff%numerical = .true.
       else if (equal(word,'analytical')) then
          ff%numerical = .false.
       else if (equal(word,'typnuc')) then
          ok = eval_next(ff%typnuc,line,lp)
          if (.not.ok) then
             call ferror("setfield","wrong typnuc",faterr,line,syntax=.true.)
             return
          end if
          if (ff%typnuc /= -3 .and. ff%typnuc /= -1 .and. &
              ff%typnuc /= +1 .and. ff%typnuc /= +3) then
             call ferror("setfield","wrong typnuc (-3,-1,+1,+3)",faterr,line,syntax=.true.)
             return
          end if
       else if (equal(word,'normalize')) then
          ok = eval_next(norm,line,lp)
          if (.not. ok) then
             call ferror('setfield','normalize real number missing',faterr,line,syntax=.true.)
             return
          end if
          ff%f = ff%f / (sum(ff%f) * cr%omega / real(product(ff%n),8)) * norm
          if (allocated(ff%c2)) deallocate(ff%c2)
       else if (equal(word,'name') .or. equal(word,'id')) then
          ok = isexpression_or_word(aux,line,lp)
          if (.not. ok) then
             call ferror('setfield','wrong name keyword',faterr,line,syntax=.true.)
             return
          end if
          ff%name = trim(aux)
          call fh%put(trim(aux),fid)
       else if (equal(word,'notestmt')) then
          if (present(dormt)) &
             dormt = .false.
       else if (len_trim(word) > 0) then
          call ferror('setfield','Unknown extra keyword',faterr,line,syntax=.true.)
          return
       else
          exit
       end if
    end do

    oksyn = .true.

  end subroutine setfield

  ! Calculate the scalar field f at point v (Cartesian) and its
  ! derivatives up to nder. Return the results in res0 or
  ! res0_noalloc. If periodic is present and false, consider the field
  ! is defined in a non-periodic system. This routine is thread-safe.
  recursive subroutine grd(f,v,nder,periodic,res0,res0_noalloc)
    use grd_atomic, only: grda_promolecular
    use grid_tools, only: grinterp
    use crystalmod, only: cr
    use dftb_private, only: dftb_rho2
    use wfn_private, only: wfn_rho2
    use pi_private, only: pi_rho2
    use elk_private, only: elk_rho2
    use wien_private, only: wien_rho2
    use arithmetic, only: eval
    use types, only: scalar_value, scalar_value_noalloc
    use tools_io, only: ferror, faterr
    use tools_math, only: norm
    type(field), intent(inout) :: f !< Input field
    real*8, intent(in) :: v(3) !< Target point in Cartesian coordinates 
    integer, intent(in) :: nder !< Number of derivatives to calculate
    logical, intent(in), optional :: periodic !< Whether the system is to be considered periodic (molecules only)
    type(scalar_value), intent(out), optional :: res0 !< Output density and related scalar properties
    type(scalar_value_noalloc), intent(out), optional :: res0_noalloc !< Output density and related scalar properties (no allocatable components)

    real*8 :: wx(3), wc(3), dist, x(3)
    integer :: i, nid, lvec(3), idx(3)
    real*8 :: rho, grad(3), h(3,3)
    real*8 :: fval(-ndif_jmax:ndif_jmax,3), fzero
    logical :: isgrid, iok, per
    type(scalar_value) :: res

    real*8, parameter :: hini = 1d-3, errcnv = 1d-8
    real*8, parameter :: neargrideps = 1d-12

    if (.not.f%init) call ferror("grd","field not initialized",faterr)

    ! initialize output quantities 
    res%f = 0d0
    res%fval = 0d0
    res%gf = 0d0
    res%hf = 0d0
    res%gfmod = 0d0
    res%gfmodval = 0d0
    res%del2f = 0d0
    res%del2fval = 0d0
    res%gkin = 0d0
    res%vir = 0d0
    res%stress = 0d0
    res%isnuc = .false.

    ! initialize flags
    if (present(periodic)) then
       per = periodic
    else
       per = .true.
    end if

    ! numerical derivatives
    res%isnuc = .false.
    if (f%numerical) then
       fzero = grd0(f,v,periodic)
       res%f = fzero
       res%gf = 0d0
       res%hf = 0d0
       if (nder > 0) then
          ! x
          fval(:,1) = 0d0
          fval(0,1) = fzero
          res%gf(1) = der1i((/1d0,0d0,0d0/),v,hini,errcnv,fval(:,1),f,grd0,periodic)
          ! y
          fval(:,2) = 0d0
          fval(0,2) = fzero
          res%gf(2) = der1i((/0d0,1d0,0d0/),v,hini,errcnv,fval(:,2),f,grd0,periodic)
          ! z
          fval(:,3) = 0d0
          fval(0,3) = fzero
          res%gf(3) = der1i((/0d0,0d0,1d0/),v,hini,errcnv,fval(:,3),f,grd0,periodic)
          if (nder > 1) then
             ! xx, yy, zz
             res%hf(1,1) = der2ii((/1d0,0d0,0d0/),v,0.5d0*hini,errcnv,fval(:,1),f,grd0,periodic)
             res%hf(2,2) = der2ii((/0d0,1d0,0d0/),v,0.5d0*hini,errcnv,fval(:,2),f,grd0,periodic)
             res%hf(3,3) = der2ii((/0d0,0d0,1d0/),v,0.5d0*hini,errcnv,fval(:,3),f,grd0,periodic)
             ! xy, xz, yz
             res%hf(1,2) = der2ij((/1d0,0d0,0d0/),(/0d0,1d0,0d0/),v,hini,hini,errcnv,f,grd0,periodic)
             res%hf(1,3) = der2ij((/1d0,0d0,0d0/),(/0d0,0d0,1d0/),v,hini,hini,errcnv,f,grd0,periodic)
             res%hf(2,3) = der2ij((/0d0,1d0,0d0/),(/0d0,0d0,1d0/),v,hini,hini,errcnv,f,grd0,periodic)
             ! final
             res%hf(2,1) = res%hf(1,2)
             res%hf(3,1) = res%hf(1,3)
             res%hf(3,2) = res%hf(2,3)
          end if
       end if
       res%gfmod = norm(res%gf)
       res%del2f = res%hf(1,1) + res%hf(2,2) + res%hf(3,3)
       ! valence quantities
       res%fval = res%f
       res%gfmodval = res%gfmod
       res%del2fval = res%hf(1,1) + res%hf(2,2) + res%hf(3,3)
       goto 999
    end if

    ! To the main cell. Add a small safe zone around the limits of the unit cell
    ! to prevent precision problems.
    wx = cr%c2x(v)
    if (per) then
       do i = 1, 3
          if (wx(i) < -flooreps .or. wx(i) > 1d0+flooreps) &
             wx(i) = wx(i) - real(floor(wx(i)),8)
       end do
    else
       if (.not.cr%ismolecule) &
          call ferror("grd","non-periodic calculation in a crystal",faterr)
       ! if outside the main cell and the field is limited to a certain region of 
       ! space, nullify the result and exit
       if ((any(wx < -flooreps) .or. any(wx > 1d0+flooreps)) .and. & 
          f%type == type_grid .or. f%type == type_wien .or. f%type == type_elk .or.&
          f%type == type_pi) then 
          goto 999
       end if
    end if
    wc = cr%x2c(wx)

    ! type selector
    select case(f%type)
    case(type_grid)
       isgrid = .false.
       if (nder == 0) then
          ! maybe we can get the grid point directly
          x = modulo(wx,1d0) * f%n
          idx = nint(x)
          isgrid = all(abs(x-idx) < neargrideps)
       end if
       if (isgrid) then
          idx = modulo(idx,f%n)+1
          res%f = f%f(idx(1),idx(2),idx(3))
          res%gf = 0d0
          res%hf = 0d0
       else
          call grinterp(f,wx,res%f,res%gf,res%hf)
          res%gf = matmul(transpose(cr%car2crys),res%gf)
          res%hf = matmul(matmul(transpose(cr%car2crys),res%hf),cr%car2crys)
       endif

    case(type_wien)
       call wien_rho2(f,wx,res%f,res%gf,res%hf)
       res%gf = matmul(transpose(cr%car2crys),res%gf)
       res%hf = matmul(matmul(transpose(cr%car2crys),res%hf),cr%car2crys)

    case(type_elk)
       call elk_rho2(f,wx,nder,res%f,res%gf,res%hf)
       res%gf = matmul(transpose(cr%car2crys),res%gf)
       res%hf = matmul(matmul(transpose(cr%car2crys),res%hf),cr%car2crys)

    case(type_pi)
       call pi_rho2(f,wc,res%f,res%gf,res%hf)
       ! transformation not needed because of pi_register_struct:
       ! all work done in cartesians in a finite environment.

    case(type_wfn)
       call wfn_rho2(f,wc,nder,res%f,res%gf,res%hf,res%gkin,res%vir,res%stress,res%mo)
       ! transformation not needed because all work done in cartesians
       ! in a finite environment. wfn assumes the crystal structure
       ! resulting from load xyz/wfn/wfx (molecule at the center of 
       ! a big cube).

    case(type_dftb)
       call dftb_rho2(f,wc,nder,res%f,res%gf,res%hf,res%gkin)
       ! transformation not needed because of dftb_register_struct:
       ! all work done in cartesians in a finite environment.

    case(type_promol)
       call grda_promolecular(wc,res%f,res%gf,res%hf,nder,.false.,periodic=periodic)
       ! not needed because grd_atomic uses struct.

    case(type_promol_frag)
       call grda_promolecular(wc,res%f,res%gf,res%hf,nder,.false.,f%fr,periodic=periodic)
       ! not needed because grd_atomic uses struct.

    case(type_ghost)
       res%f = eval(f%expr,.true.,iok,wc,fields_fcheck,fields_feval,periodic)
       res%gf = 0d0
       res%hf = 0d0

    case default
       call ferror("grd","unknown scalar field type",faterr)
    end select

    ! save the valence-only value
    res%fval = res%f
    res%gfmodval = res%gfmod
    res%del2fval = res%hf(1,1) + res%hf(2,2) + res%hf(3,3)

    ! augment with the core if applicable
    if (f%usecore .and. any(cr%at(1:cr%nneq)%zpsp /= -1)) then
       call grda_promolecular(wc,rho,grad,h,nder,.true.,periodic=periodic)
       res%f = res%f + rho
       res%gf  = res%gf + grad
       res%hf = res%hf + h
    end if

    ! If it's on a nucleus, nullify the gradient (may not be zero in
    ! grid fields, for instance)
    nid = 0
    call cr%nearest_atom(wx,nid,dist,lvec)
    if (per .or. .not.per .and. all(lvec == 0)) then
       res%isnuc = (dist < 1d-5)
       if (res%isnuc) res%gf = 0d0
    end if
    res%gfmod = norm(res%gf)
    res%del2f = res%hf(1,1) + res%hf(2,2) + res%hf(3,3)

999 continue
    if (present(res0)) res0 = res
    if (present(res0_noalloc)) then
       res0_noalloc%f = res%f
       res0_noalloc%fval = res%fval
       res0_noalloc%gf = res%gf
       res0_noalloc%hf = res%hf
       res0_noalloc%gfmod = res%gfmod
       res0_noalloc%gfmodval = res%gfmodval
       res0_noalloc%del2f = res%del2f
       res0_noalloc%del2fval = res%del2fval
       res0_noalloc%gkin = res%gkin
       res0_noalloc%stress = res%stress
       res0_noalloc%vir = res%vir
       res0_noalloc%hfevec = res%hfevec
       res0_noalloc%hfeval = res%hfeval
       res0_noalloc%r = res%r
       res0_noalloc%s = res%s
       res0_noalloc%isnuc = res%isnuc
    end if

  end subroutine grd

  !> Calculate the value of all integrable properties at the given position
  !> xpos (Cartesian). This routine is thread-safe.
  subroutine grdall(xpos,lprop,pmask)
    use arithmetic, only: eval
    use tools_io, only: ferror, faterr
    use types, only: scalar_value

    real*8, intent(in) :: xpos(3) !< Point (cartesian).
    real*8, intent(out) :: lprop(nprops) !< the properties vector.
    logical, intent(in), optional :: pmask(nprops) !< properties mask

    type(scalar_value) :: res(0:ubound(f,1))
    logical :: fdone(0:ubound(f,1)), iok, pmask0(nprops)
    integer :: i, id

    if (present(pmask)) then
       pmask0 = pmask
    else
       pmask0 = .true.
    end if

    lprop = 0d0
    fdone = .false.
    do i = 1, nprops
       if (.not.pmask0(i)) cycle
       if (.not.integ_prop(i)%used) cycle
       if (integ_prop(i)%itype == itype_expr) then
          lprop(i) = eval(integ_prop(i)%expr,.true.,iok,xpos,fields_fcheck,fields_feval)
       else
          id = integ_prop(i)%fid
          if (.not.fused(id)) cycle
          if (.not.fdone(id).and.integ_prop(i)%itype /= itype_v) then
             call grd(f(id),xpos,2,res0=res(id))
             fdone(id) = .true.
          end if

          select case(integ_prop(i)%itype)
          case(itype_v)
             lprop(i) = 1
          case(itype_f)
             lprop(i) = res(id)%f
          case(itype_fval)
             lprop(i) = res(id)%fval
          case(itype_gmod)
             lprop(i) = res(id)%gfmod
          case(itype_lap)
             lprop(i) = res(id)%del2f
          case(itype_lapval)
             lprop(i) = res(id)%del2fval
          case(itype_mpoles)
             lprop(i) = res(id)%f
          case(itype_deloc)
             lprop(i) = res(id)%f
          case default
             call ferror('grdall','unknown property',faterr)
          end select
       end if
    end do

  end subroutine grdall

  !> Calculate only the value of the scalar field at the given point
  !> (v in cartesian). If periodic is present and false, consider the
  !> field is defined in a non-periodic system. This routine is
  !> thread-safe.
  recursive function grd0(f,v,periodic)
    use grd_atomic, only: grda_promolecular
    use grid_tools, only: grinterp
    use crystalmod, only: cr
    use dftb_private, only: dftb_rho2
    use wfn_private, only: wfn_rho2
    use pi_private, only: pi_rho2
    use elk_private, only: elk_rho2
    use wien_private, only: wien_rho2
    use arithmetic, only: eval
    ! use types
    use tools_io, only: ferror, faterr
    ! use tools_math
    type(field), intent(inout) :: f
    real*8, dimension(3), intent(in) :: v !< Target point in cartesian or spherical coordinates.
    real*8 :: grd0
    logical, intent(in), optional :: periodic !< Whether the system is to be considered periodic (molecules only)

    real*8 :: wx(3), wc(3)
    integer :: i
    real*8 :: h(3,3), grad(3), rho, rhoaux, gkin, vir, stress(3,3)
    logical :: iok, per

    ! initialize 
    if (present(periodic)) then
       per = periodic
    else
       per = .true.
    end if
    grd0 = 0d0

    ! To the main cell. Add a small safe zone around the limits of the unit cell
    ! to prevent precision problems.
    wx = cr%c2x(v)
    if (per) then
       do i = 1, 3
          if (wx(i) < -flooreps .or. wx(i) > 1d0+flooreps) &
             wx(i) = wx(i) - real(floor(wx(i)),8)
       end do
    else
       if (.not.cr%ismolecule) &
          call ferror("grd","non-periodic calculation in a crystal",faterr)
       ! if outside the main cell and the field is limited to a certain region of 
       ! space, nullify the result and exit
       if ((any(wx < -flooreps) .or. any(wx > 1d0+flooreps)) .and. & 
          f%type == type_grid .or. f%type == type_wien .or. f%type == type_elk .or.&
          f%type == type_pi) then 
          return
       end if
    end if
    wc = cr%x2c(wx)

    ! type selector
    select case(f%type)
    case(type_grid)
       call grinterp(f,wx,rho,grad,h)
    case(type_wien)
       call wien_rho2(f,wx,rho,grad,h)
    case(type_elk)
       call elk_rho2(f,wx,0,rho,grad,h)
    case(type_pi)
       call pi_rho2(f,wc,rho,grad,h)
    case(type_wfn)
       call wfn_rho2(f,wc,0,rho,grad,h,gkin,vir,stress)
    case(type_dftb)
       call dftb_rho2(f,wc,0,rho,grad,h,gkin)
    case(type_promol)
       call grda_promolecular(wc,rho,grad,h,0,.false.,periodic=periodic)
    case(type_promol_frag)
       call grda_promolecular(wc,rho,grad,h,0,.false.,f%fr,periodic=periodic)
    case(type_ghost)
       rho = eval(f%expr,.true.,iok,wc,fields_fcheck,fields_feval,periodic)
    case default
       call ferror("grd","unknown scalar field type",faterr)
    end select

    if (f%usecore .and. any(cr%at(1:cr%nneq)%zpsp /= -1)) then
       call grda_promolecular(wc,rhoaux,grad,h,0,.true.,periodic=periodic)
       rho = rho + rhoaux
    end if
    grd0 = rho

  end function grd0

  !> Return a string description of the field type.
  function fields_typestring(itype) result(s)
    use tools_io, only: faterr, ferror
    integer, intent(in) :: itype
    character(len=:), allocatable :: s
    
    select case (itype)
    case (type_promol)
       s = "promolecular"
    case (type_grid)
       s = "grid"
    case (type_wien)
       s = "wien2k"
    case (type_elk)
       s = "elk"
    case (type_pi)
       s = "pi"
    case (type_wfn)
       s = "molecular wavefunction"
    case (type_dftb)
       s = "dftb+"
    case (type_promol_frag)
       s = "promolecular fragment"
    case (type_ghost)
       s = "ghost field"
    case default
       call ferror('fields_typestring','unknown field type',faterr)
    end select

  endfunction fields_typestring

  !> Do a benchmark of the speed of the external module in calculating grd and grdall
  !> by using npts random points in the unit cell.
  subroutine benchmark(npts)
    use crystalmod, only: cr
    use global, only: refden
    use tools_io, only: uout
    use types, only: scalar_value
    use wien_private, only: wien_rmt_atom
    use elk_private, only: elk_rmt_atom
    implicit none

    integer, intent(in) :: npts

    integer :: wpts(cr%nneq+1)
    integer :: i, j
    real*8 :: x(3), aux(3), dist
    integer :: c1, c2, rate
    real*8, allocatable :: randn(:,:,:)
    type(scalar_value) :: res
    logical :: inrmt

    write (uout,'("* Benchmark of the field ")')
    write (uout,'("* Field : ",I2)') refden

    if (f(refden)%type == type_wien .or. f(refden)%type == type_elk) then
       wpts = 0
       allocate(randn(3,npts,cr%nneq+1))

       out: do while (any(wpts(1:cr%nneq+1) < npts))
          call random_number(x)
          do i = 1, cr%ncel
             if (cr%atcel(i)%idx > cr%nneq) cycle
             aux = x - cr%atcel(i)%x
             aux = cr%x2c(aux - nint(aux))
             dist = dot_product(aux,aux)
             if (f(refden)%type == type_wien) then
                inrmt = (dist < wien_rmt_atom(f(refden),cr%at(cr%atcel(i)%idx)%x)**2)
             else
                inrmt = (dist < elk_rmt_atom(f(refden),cr%at(cr%atcel(i)%idx)%x)**2)
             end if
             if (inrmt) then
                if (wpts(cr%atcel(i)%idx) >= npts) cycle out
                wpts(cr%atcel(i)%idx) = wpts(cr%atcel(i)%idx) + 1
                randn(:,wpts(cr%atcel(i)%idx),cr%atcel(i)%idx) = cr%x2c(x)
                cycle out
             end if
          end do
          if (wpts(cr%nneq+1) >= npts) cycle out
          wpts(cr%nneq+1) = wpts(cr%nneq+1) + 1
          randn(:,wpts(cr%nneq+1),cr%nneq+1) = cr%x2c(x)
       end do out

       write (uout,'("* Benchmark of muffin / interstitial grd ")')
       write (uout,'("* Number of points per zone : ",I8)') npts
       do i = 1, cr%nneq+1
          call system_clock(count=c1,count_rate=rate)
          do j = 1, npts
             call grd(f(refden),randn(:,j,i),0,res0=res)
          end do
          call system_clock(count=c2)
          if (i <= cr%nneq) then
             write (uout,'("* Atom : ",I3)') i
          else
             write (uout,'("* Interstitial ")')
          end if
          write (uout,'("* Total wall time : ",F20.6," s ")') real(c2-c1,8) / rate
          write (uout,'("* Avg. wall time per call : ",F20.8," us ")') &
             real(c2-c1,8) / rate / real(npts,8) * 1d6
       end do
       write (uout,*)
       deallocate(randn)

    else
       allocate(randn(3,npts,1))

       call random_number(randn)
       do i = 1, npts
          randn(1:3,i,1) = cr%x2c(randn(1:3,i,1))
       end do

       ! grd
       write (uout,'("  Benchmark of the grd call ")')
       write (uout,'("  Number of points : ",I8)') npts
       call system_clock(count=c1,count_rate=rate)
       do i = 1, npts
          call grd(f(refden),randn(:,i,1),0,res0=res)
       end do
       call system_clock(count=c2)
       write (uout,'("  Total wall time : ",F20.6," s ")') real(c2-c1,8) / rate
       write (uout,'("  Avg. wall time per call : ",F20.8," us ")') &
          real(c2-c1,8) / rate / real(npts,8) * 1d6
       write (uout,*)

       ! ! grdall
       ! write (uout,'("* Benchmark of the grdall call ")')
       ! write (uout,'("* Number of points : ",I8)') npts
       ! call system_clock(count=c1,count_rate=rate)
       ! do i = 1, npts
       !    call grdall(randn(:,i,1),dumprop,dumatom)
       ! end do
       ! call system_clock(count=c2)
       ! write (uout,'("* Total wall time : ",F20.6," s ")') real(c2-c1,8) / rate
       ! write (uout,'("* Avg. wall time per call : ",F20.8," us ")') &
       !    real(c2-c1,8) / rate / real(npts,8) * 1d6
       ! write (uout,*)

       deallocate(randn)

    end if

  end subroutine benchmark

  ! test the muffin tin discontinuity
  subroutine testrmt(id,ilvl)
    use crystalmod, only: cr
    ! use global
    use tools_io, only: uout, ferror, warning, string, fopen_write, fclose
    use wien_private, only: wien_rmt_atom
    use elk_private, only: elk_rmt_atom
    use types, only: scalar_value
    use param, only: pi
    integer, intent(in) :: id, ilvl

    integer :: n, i, j
    integer :: ntheta, nphi
    integer :: nt, np
    real*8 :: phi, theta, dir(3), xnuc(3), xp(3)
    real*8 :: fin, fout, gfin, gfout
    real*8 :: r, rmt
    character*4 :: label
    character(len=:), allocatable :: linefile
    integer :: luline, luplane
    integer  :: npass(cr%nneq), nfail(cr%nneq)
    logical :: ok
    real*8 :: epsm, epsp, mepsm, mepsp, dif, dosum, mindif, maxdif
    type(scalar_value) :: res

    real*8, parameter :: eps = 1d-3

    if (f(id)%type /= type_wien .and. f(id)%type /= type_elk) return

    write (uout,'("* Muffin-tin discontinuity test")')

    ntheta = 10
    nphi = 10
    do n = 1, cr%nneq
       if (f(id)%type == type_wien) then
          rmt = wien_rmt_atom(f(id),cr%at(n)%x)
       else
          rmt = elk_rmt_atom(f(id),cr%at(n)%x)
       end if
       mepsm = 0d0
       mepsp = 0d0
       if (ilvl > 1) then
          write (uout,'("+ Analysis of the muffin tin discontinuity for atom ",A)') string(n)
          write (uout,'("  ntheta = ",A)') string(ntheta)
          write (uout,'("  nphi = ",A)') string(nphi)
       end if

       xnuc = cr%at(n)%x
       if (ilvl > 1) write (uout,'("  coords = ",3(A,X))') (string(xnuc(j),'f',decimal=9),j=1,3)
       xnuc = cr%x2c(xnuc)

       if (ilvl > 1) then
          write (uout,'("  rmt = ",A)') string(rmt,'f',decimal=7)
          write (uout,'(2(A8,X),6(A12,X),A4)') "Azim.", "Polar", "f_in",&
             "f_out", "f_in-f_out", "gf_in", "gf_out", "gf_in-gf_out", "ok?"
          write (uout,'(100("-"))')
       end if
       npass(n) = 0
       nfail(n) = 0
       dosum = 0d0
       mindif = 1d10
       maxdif = -1d10
       if (ilvl > 1) then
          ! write line
          linefile = "plane_" // string(n,2,pad0=.true.) // ".dbg"
          luplane = fopen_write(linefile)
          write (luplane,'("#",A,I3)') " atom: ", n
          write (luplane,'("#",A,1p,3(E20.13,X))') " at: ", cr%at(n)%x
          write (luplane,'("#",A,1p,3(E20.13,X))') " atc: ", xnuc
          write (luplane,'("#",A,1p,E20.13)') " rmt: ", rmt
          write (luplane,'("#  theta phi in out")')
       end if
       do nt = 1, ntheta
          do np = 0, nphi
             if ((np == 0 .or. np == nphi) .and. nt /= 1) cycle
             phi = real(np,8) * pi / nphi
             theta = real(nt,8) * 2d0 * pi / ntheta
             dir(1) = 1d0 * cos(theta) * sin(phi)
             dir(2) = 1d0 * sin(theta) * sin(phi)
             dir(3) = 1d0 * cos(phi)

             xp = xnuc + (rmt+eps) * dir
             call grd(f(id),xp,1,res0=res)
             fout = res%f
             gfout = dot_product(res%gf,xp-xnuc) / (rmt+eps)
             xp = xnuc + (rmt-eps) * dir
             call grd(f(id),xp,1,res0=res)
             fin = res%f
             gfin = dot_product(res%gf,xp-xnuc) / (rmt-eps)

             dif = fout - fin
             dosum = dosum + dif * dif
             if (dif < mindif) mindif = dif
             if (dif > maxdif) maxdif = dif

             if (ilvl > 1) then
                ! write line
                write (luplane,'(1p,4(E20.13,X))') theta, phi, fin, fout
             end if

             if (gfin*gfout > 0d0) then
                label = "pass"
                npass(n) = npass(n) + 1
             else
                label = "fail"
                if (ilvl > 2) then
                   ! write line
                   linefile = "line_" // string(n,2,pad0=.true.) // "_" // string(nt,3,pad0=.true.) //&
                      "_" // string(np,3,pad0=.true.) // ".dbg"
                   luline = fopen_write(linefile)
                   write (luline,'("#",A,I3)') " atom: ", n
                   write (luline,'("#",A,1p,3(E20.13,X))') " at: ", cr%at(n)%x
                   write (luline,'("#",A,1p,3(E20.13,X))') " atc: ", xnuc
                   write (luline,'("#",A,1p,E20.13)') " rmt: ", rmt
                   write (luline,'("#",A,1p,3(E20.13,X))') " dir: ", dir
                   write (luline,'("#",A,1p,E20.13)') " r_ini: ", 0.50d0 * rmt
                   write (luline,'("#",A,1p,E20.13)') " r_end: ", 4.50d0 * rmt
                   do i = 0, 1000
                      r = 0.50d0 * rmt + (real(i,8) / 1000) * 4d0 * rmt
                      xp = xnuc + r * dir
                      call grd(f(id),xp,1,res0=res)
                      write (luline,'(1p,3(E20.13,X))') r, res%f, dot_product(res%gf,xp-xnuc) / r
                   end do
                   call fclose(luline)
                end if
                epsm = 0d0
                epsp = 0d0
                mepsm = min(epsm,mepsm)
                mepsp = max(epsp,mepsp)
                nfail(n) = nfail(n) + 1
             end if
             if (ilvl > 1) write (uout,'(2(F8.4,X),1p,6(E12.4,X),0p,A4)') &
                theta, phi, fin, fout, fin-fout, gfin, gfout, gfin-gfout, label
          end do
       end do
       dosum = sqrt(dosum / (npass(n)+nfail(n)))
       if (ilvl > 1) then
          write (uout,'(100("-"))')
          write (uout,*)
       end if
       if (ilvl > 1) then
          call fclose(luplane)
       end if
       if (nfail(n) > 0) then
          write (uout,'("  Atom: ",A," delta_m = ",A," delta_p = ",A)') &
             string(n), string(mepsm+1d-3,'f',decimal=6), string(mepsp+1d-3,'f',decimal=6)
          write (uout,*)
       end if
       write (uout,'("  Atom: ",A," rmt= ",A," RMS/max/min(fout-fin) = ",3(A,2X))') &
          string(n), string(rmt,'f',decimal=7), string(dosum,'f',decimal=6), &
          string(maxdif,'f',decimal=6), string(mindif,'f',decimal=6)
    end do

    ok = .true.
    if (ilvl > 0) then
       write (uout,'("+ Summary ")')
       write (uout,'(A4,3(X,A7))') "Atom", "Pass", "Fail", "Total"
    end if
    do n = 1, cr%nneq
       if (ilvl > 0) write (uout,'(I4,3(X,I7))') n, npass(n), nfail(n), npass(n)+nfail(n)
       ok = ok .and. (nfail(n) == 0)
    end do
    if (ilvl > 0) write (uout,*)
    write (uout,'("+ Assert - no spurious CPs on the muffin tin surface: ",L1/)') ok
    if (.not.ok) call ferror('testrmt','Spurious CPs on the muffin tin surface!',warning)

  end subroutine testrmt

  !> Calculate the kinetic energy density from the elf
  subroutine taufromelf(ielf,irho,itau)
    use grid_tools, only: grid_gradrho
    use tools_io, only: ferror, faterr, string, fclose
    use param, only: fh, pi
    integer, intent(in) :: ielf, irho, itau

    integer :: igrad
    real*8, allocatable :: g(:,:,:)

    ! check that the fields are good
    if (.not.goodfield(ielf,type_grid)) &
       call ferror("taufromelf","wrong elf field",faterr)
    if (.not.goodfield(irho,type_grid)) &
       call ferror("taufromelf","wrong rho field",faterr)
    if (any(f(ielf)%n /= f(irho)%n)) &
       call ferror("taufromelf","incongruent sizes of rho and elf",faterr)

    ! copy the elf field for now
    if (allocated(f(itau)%c2)) deallocate(f(itau)%c2)
    f(itau) = f(ielf)
    fused(itau) = .true.
    call fh%put(string(itau),itau)
    if (allocated(f(itau)%f)) deallocate(f(itau)%f)

    ! allocate a temporary field for the gradient
    igrad = getfieldnum()
    call grid_gradrho(f(irho),f(igrad))
    
    allocate(g(f(ielf)%n(1),f(ielf)%n(2),f(ielf)%n(3)))
    g = sqrt(1d0 / max(min(f(ielf)%f,1d0),1d-14) - 1d0)
    g = g * (3d0/10d0 * (3d0*pi**2)**(2d0/3d0) * max(f(irho)%f,0d0)**(5d0/3d0))
    g = g + 0.125d0 * f(igrad)%f**2 / f(irho)%f
    call move_alloc(g,f(itau)%f)

    ! unload the temporary field
    call fields_unload(igrad)

  end subroutine taufromelf

  !> Convert a field name to the corresponding integer index.
  function fieldname_to_idx(id) result(fid)
    use param, only: fh
    character*(*), intent(in) :: id
    integer :: fid

    character(len=:), allocatable :: oid
    integer :: ierr

    oid = trim(adjustl(id))
    if (fh%iskey(oid)) then 
       fid = fh%get(oid,fid)
    else
       read(oid,*,iostat=ierr) fid
       if (ierr /= 0) fid = -1
    endif

  end function fieldname_to_idx

  !> Write information about the field to the standard output.  isload
  !> = show load-time information, isset = show flags for this field.
  subroutine fieldinfo(id,isload,isset)
    use crystalmod
    use global, only: dunit0, iunit, iunitname0
    use tools_io
    integer, intent(in) :: id
    logical, intent(in) :: isload, isset
    
    integer :: i, j, k, n(3)

    ! check that we have an environment
    call cr%checkflags(.true.,env0=.true.)

    ! header
    write (uout,'("* Scalar field number: ",A)') string(id)
    if (.not.f(id)%init) then
       write (uout,'("  Not initialized! ")')
       return
    end if
       
    ! general information about the field
    if (len_trim(f(id)%name) > 0) &
       write (uout,'("  Name: ",A)') string(f(id)%name)
    if (len_trim(f(id)%file) > 0) then
       write (uout,'("  Source: ",A)') string(f(id)%file)
    else
       write (uout,'("  Source: <generated>")')
    end if
    write (uout,'("  Type: ",A)') fields_typestring(f(id)%type)

    ! type-specific
    if (f(id)%type == type_promol) then
       ! promolecular densities
       if (isload) then
          write (uout,'("  Atoms in the environment: ",A)') string(cr%nenv)
       end if
    elseif (f(id)%type == type_grid) then
       ! grids
       n = f(id)%n
       if (isload) then
          write (uout,'("  Grid dimensions : ",3(A,2X))') (string(f(id)%n(j)),j=1,3)
          write (uout,'("  First elements... ",3(A,2X))') (string(f(id)%f(1,1,j),'e',decimal=12),j=1,3)
          write (uout,'("  Last elements... ",3(A,2X))') (string(f(id)%f(n(1),n(2),n(3)-2+j),'e',decimal=12),j=0,2)
          write (uout,'("  Sum of elements... ",A)') string(sum(f(id)%f(:,:,:)),'e',decimal=12)
          write (uout,'("  Sum of squares of elements... ",A)') string(sum(f(id)%f(:,:,:)**2),'e',decimal=12)
          write (uout,'("  Cell integral (grid SUM) = ",A)') &
             string(sum(f(id)%f) * cr%omega / real(product(f(id)%n),8),'f',decimal=8)
          write (uout,'("  Min: ",A)') string(minval(f(id)%f),'e',decimal=8)
          write (uout,'("  Average: ",A)') string(sum(f(id)%f) / real(product(f(id)%n),8),'e',decimal=8)
          write (uout,'("  Max: ",A)') string(maxval(f(id)%f),'e',decimal=8)
       end if
       if (isset) then
          write (uout,'("  Interpolation mode (1=nearest,2=linear,3=spline,4=tricubic): ",A)') string(f(id)%mode)
       end if
    elseif (f(id)%type == type_wien) then
       if (isload) then
          write (uout,'("  Complex?: ",L)') f(id)%cmpl
          write (uout,'("  Spherical harmonics expansion LMmax: ",A)') string(size(f(id)%lm,2))
          write (uout,'("  Max. points in radial grid: ",A)') string(size(f(id)%slm,1))
          write (uout,'("  Total number of plane waves (new/orig): ",A,"/",A)') string(f(id)%nwav), string(f(id)%lastind)
       end if
       if (isset) then
          write (uout,'("  Density-style normalization? ",L)') f(id)%cnorm
       end if
    elseif (f(id)%type == type_elk) then
       if (isload) then
          write (uout,'("  Number of LM pairs: ",A)') string(size(f(id)%rhomt,2))
          write (uout,'("  Max. points in radial grid: ",A)') string(size(f(id)%rhomt,1))
          write (uout,'("  Total number of plane waves: ",A)') string(size(f(id)%rhok))
       end if
    elseif (f(id)%type == type_pi) then
       if (isset) then
          write (uout,'("  Exact calculation? ",L)') f(id)%exact
       end if
    elseif (f(id)%type == type_wfn) then
       if (isload) then
          write (uout,'("  Number of MOs: ",A)') string(f(id)%nmo)
          write (uout,'("  Number of primitives: ",A)') string(f(id)%npri)
          write (uout,'("  Wavefunction type (0=closed,1=open,2=frac): ",A)') string(f(id)%wfntyp)
          write (uout,'("  Number of EDFs: ",A)') string(f(id)%nedf)
       end if
    elseif (f(id)%type == type_dftb) then
       if (isload) then
          write (uout,'("  Number of states: ",A)') string(f(id)%nstates)
          write (uout,'("  Number of spin channels: ",A)') string(f(id)%nspin)
          write (uout,'("  Number of orbitals: ",A)') string(f(id)%norb)
          write (uout,'("  Number of kpoints: ",A)') string(f(id)%nkpt)
          write (uout,'("  Real wavefunction? ",L)') f(id)%isreal
       end if
       if (isset) then
          write (uout,'("  Exact calculation? ",L)') f(id)%exact
       end if
    elseif (f(id)%type == type_promol_frag) then
       if (isload) then
          write (uout,'("  Number of atoms in fragment: ",A)') string(f(id)%fr%nat)
       end if
    elseif (f(id)%type == type_ghost) then
       write (uout,'("  Expression: ",A)') string(f(id)%expr)
    else
       call ferror("fieldinfo","unknown field type",faterr)
    end if

    ! flags for any field
    if (isset) then
       write (uout,'("  Use core densities? ",L)') f(id)%usecore
       write (uout,'("  Numerical derivatives? ",L)') f(id)%numerical
       write (uout,'("  Nuclear CP signature: ",A)') string(f(id)%typnuc)
    end if

    ! Wannier information
    if (f(id)%iswan) then
       write (uout,*)
       write (uout,'("+ Wannier functions available for this field")') 
       if (f(id)%wan%haschk) then
          write (uout,'("  Source: sij-chk checkpoint file")') 
       else
          if (allocated(f(id)%wan%ngk)) then
             write (uout,'("  Source: unkgen")') 
          else
             write (uout,'("  Source: UNK files")') 
          end if
       endif
       write (uout,'("  Real-space lattice vectors: ",3(A,X))') (string(f(id)%wan%nwan(i)),i=1,3)
       write (uout,'("  Number of bands: ",A)') string(f(id)%wan%nbnd)
       write (uout,'("  Number of spin channels: ",A)') string(f(id)%wan%nspin)
       if (f(id)%wan%cutoff > 0d0) &
          write (uout,'("  Overlap calculation distance cutoff: ",A)') string(f(id)%wan%cutoff,'f',10,4)
       write (uout,'("  List of k-points: ")')
       do i = 1, f(id)%wan%nks
          write (uout,'(4X,A,A,99(X,A))') string(i),":", (string(f(id)%wan%kpt(j,i),'f',8,4),j=1,3)
       end do
       write (uout,'("  Wannier function centers (cryst. coords.) and spreads: ")')
       write (uout,'("# bnd spin        ----  center  ----        spread(",A,")")') iunitname0(iunit)
       do i = 1, f(id)%wan%nspin
          do j = 1, f(id)%wan%nbnd
             write (uout,'(2X,99(A,X))') string(j,4,ioj_center), string(i,2,ioj_center), &
                (string(f(id)%wan%center(k,j,i),'f',10,6,4),k=1,3),&
                string(f(id)%wan%spread(j,i) * dunit0(iunit),'f',14,8,4)
          end do
       end do
    end if

    write (uout,*)

  end subroutine fieldinfo

  !> Check that the id is a grid and is a sane field. Wrapper
  !> around goodfield() to pass it to the arithmetic module.
  !> This routine is thread-safe.
  function fields_fcheck(id,iout)
    logical :: fields_fcheck
    character*(*), intent(in) :: id
    integer, intent(out), optional :: iout

    integer :: iid

    iid = fieldname_to_idx(id)
    fields_fcheck = goodfield(iid)
    if (present(iout)) iout = iid

  end function fields_fcheck

  !> Evaluate the field at a point. Wrapper around grd() to pass it to
  !> the arithmetic module.  This routine is thread-safe.
  recursive function fields_feval(id,nder,x0,periodic)
    use crystalmod, only: cr
    use types, only: scalar_value
    use param, only: sqpi, pi
    type(scalar_value) :: fields_feval
    character*(*), intent(in) :: id
    integer, intent(in) :: nder
    real*8, intent(in) :: x0(3)
    logical, intent(in), optional :: periodic

    integer :: iid, lvec(3)
    real*8 :: xp(3), dist, u
    real*8, parameter :: rc = 1.4d0

    iid = fieldname_to_idx(id)
    if (iid >= 0) then
       call grd(f(iid),x0,nder,periodic,res0=fields_feval)
    elseif (trim(id) == "ewald") then
       xp = cr%c2x(x0)
       fields_feval%f = cr%ewald_pot(xp,.false.)
       fields_feval%fval = fields_feval%f
       fields_feval%gf = 0d0
       fields_feval%gfmod = 0d0
       fields_feval%gfmodval = 0d0
       fields_feval%hf = 0d0
       fields_feval%del2f = 0d0
       fields_feval%del2fval = 0d0
    elseif (trim(id) == "model1r") then
       ! xxxx
       iid = 0
       xp = cr%c2x(x0)
       call cr%nearest_atom(xp,iid,dist,lvec)
       if (dist < rc) then
          u = dist/rc
          fields_feval%f = (1 - 10*u**3 + 15*u**4 - 6*u**5) * 21d0 / (5d0 * pi * rc**3)
       else
          fields_feval%f = 0d0
       end if
       fields_feval%fval = fields_feval%f
       fields_feval%gf = 0d0
       fields_feval%gfmod = 0d0
       fields_feval%gfmodval = 0d0
       fields_feval%hf = 0d0
       fields_feval%del2f = 0d0
       fields_feval%del2fval = 0d0
    elseif (trim(id) == "model1v") then
       ! xxxx requires the +1 charges
       iid = 0
       xp = cr%c2x(x0)
       call cr%nearest_atom(xp,iid,dist,lvec)
       fields_feval%f = cr%ewald_pot(xp,.false.) + cr%qsum * cr%eta**2 * pi / cr%omega 
       if (dist < rc .and. dist > 1d-6) then ! correlates with the value in the ewald routine
          u = dist/rc
          fields_feval%f = fields_feval%f + (12 - 14*u**2 + 28*u**5 - 30*u**6 + 9*u**7) / (5d0 * rc) - 1d0 / dist
       elseif (dist <= 1d-6) then
          u = dist/rc
          fields_feval%f = fields_feval%f + (12 - 14*u**2 + 28*u**5 - 30*u**6 + 9*u**7) / (5d0 * rc) - 2d0 / sqpi / cr%eta
       end if
       fields_feval%fval = fields_feval%f
       fields_feval%gf = 0d0
       fields_feval%gfmod = 0d0
       fields_feval%gfmodval = 0d0
       fields_feval%hf = 0d0
       fields_feval%del2f = 0d0
       fields_feval%del2fval = 0d0
    end if

  end function fields_feval

  !> Function derivative using finite differences and Richardson's
  !> extrapolation formula. This routine is thread-safe.
  function der1i (dir, x, h, errcnv, pool, fld, grd0, periodic)
    use types, only: field

    real*8 :: der1i
    real*8, intent(in) :: dir(3)
    real*8, intent(in) :: x(3), h, errcnv
    real*8, intent(inout) :: pool(-ndif_jmax:ndif_jmax)
    type(field), intent(inout) :: fld
    logical, intent(in), optional :: periodic
    interface
       function grd0(f,v,periodic)
         use types
         type(field), intent(inout) :: f
         real*8, intent(in) :: v(3)
         real*8 :: grd0
         logical, intent(in), optional :: periodic
       end function grd0
    end interface

    real*8 :: err
    real*8 :: ww, hh, erract, n(ndif_jmax,ndif_jmax)
    real*8 :: f, fp, fm
    integer :: i, j
    integer :: nh

    der1i = 0d0
    nh = 0
    hh = h
    if (pool(nh+1) == 0d0) then
       f = grd0(fld,x+dir*hh,periodic)
       pool(nh+1) = f
    else
       f = pool(nh+1)
    end if
    fp = f
    if (pool(nh+1) == 0d0) then
       f = grd0(fld,x-dir*hh,periodic)
       pool(-nh-1) = f
    else
       f = pool(-nh-1)
    end if
    fm = f
    n(1,1) = (fp - fm) / (hh+hh)

    err = big
    do j = 2, ndif_jmax
       hh = hh / derw
       nh = nh + 1
       if (pool(nh+1) == 0d0) then
          f = grd0(fld,x+dir*hh,periodic)
          pool(nh+1) = f
       else
          f = pool(nh+1) 
       end if
       fp = f
       if (pool(-nh-1) == 0d0) then
          f = grd0(fld,x-dir*hh,periodic)
          pool(-nh-1) = f
       else
          f = pool(-nh-1) 
       end if
       fm = f
       n(1,j) = (fp - fm) / (hh+hh)
       ww = derw2
       do i = 2, j
          n(i,j) = (ww*n(i-1,j)-n(i-1,j-1))/(ww-1d0)
          ww = ww * derw2
          erract = max (abs(n(i,j)-n(i-1,j)), abs(n(i,j)-n(i-1,j-1)))
          if (erract.le.err) then
             err = erract
             der1i = n(i,j)
          endif
       enddo
       if ( abs(n(j,j)-n(j-1,j-1)) .gt. safe*err .or. err .le. errcnv ) return
    enddo

  end function der1i

  !> Function second derivative using finite differences and
  !> Richardson's extrapolation formula. This routine is thread-safe.
  function der2ii (dir, x, h, errcnv, pool, fld, grd0, periodic)
    use types, only: field
    real*8 :: der2ii
    real*8, intent(in) :: dir(3)
    real*8, intent(in) :: x(3), h, errcnv
    real*8, intent(inout) :: pool(-ndif_jmax:ndif_jmax)
    type(field), intent(inout) :: fld
    logical, intent(in), optional :: periodic
    interface
       function grd0(f,v,periodic)
         use types
         type(field), intent(inout) :: f
         real*8, intent(in) :: v(3)
         real*8 :: grd0
         logical, intent(in), optional :: periodic
       end function grd0
    end interface

    real*8 :: err

    real*8 :: ww, hh, erract, n(ndif_jmax, ndif_jmax)
    real*8 :: fx, fp, fm, f
    integer :: i, j
    integer :: nh

    der2ii = 0d0
    nh = 0
    hh = h
    if (pool(nh) == 0d0) then
       f = grd0(fld,x,periodic)
       pool(nh) = f
    else
       f = pool(nh)
    end if
    fx = 2 * f
    if (pool(nh-1) == 0d0) then
       f = grd0(fld,x-dir*(hh+hh),periodic)
       pool(nh-1) = f
    else
       f = pool(nh-1)
    end if
    fm = f
    if (pool(nh+1) == 0d0) then
       f = grd0(fld,x+dir*(hh+hh),periodic)
       pool(nh+1) = f
    else
       f = pool(nh+1)
    end if
    fp = f
    n(1,1) = (fp - fx + fm) / (4d0*hh*hh)
    err = big
    do j = 2, ndif_jmax
       hh = hh / derw
       nh = nh + 1
       if (pool(nh+1) == 0d0) then
          f = grd0(fld,x-dir*(hh+hh),periodic)
          pool(nh+1) = f
       else
          f = pool(nh+1)
       end if
       fm = f
       if (pool(-nh-1) == 0d0) then
          f = grd0(fld,x+dir*(hh+hh),periodic)
          pool(-nh-1) = f
       else
          f = pool(-nh-1)
       end if
       fp = f
       n(1,j) = (fp - fx + fm) / (4d0*hh*hh)
       ww = derw2
       erract = 0d0
       do i = 2, j
          n(i,j) = (ww*n(i-1,j)-n(i-1,j-1))/(ww-1d0)
          ww = ww * derw2
          erract = max (abs(n(i,j)-n(i-1,j)), abs(n(i,j)-n(i-1,j-1)))
          if (erract.le.err) then
             err = erract
             der2ii = n(i,j)
          endif
       enddo
       if (erract .gt. safe*err .or. err .le. errcnv) return
    enddo
    return
  end function der2ii

  !> Function mixed second derivative using finite differences and
  !> Richardson's extrapolation formula. This routine is thread-safe.
  function der2ij (dir1, dir2, x, h1, h2, errcnv, fld, grd0, periodic)
    use types, only: field
    real*8 :: der2ij
    real*8, intent(in) :: dir1(3), dir2(3)
    real*8, intent(in) :: x(3), h1, h2, errcnv
    type(field), intent(inout) :: fld
    logical, intent(in), optional :: periodic
    interface
       function grd0(f,v,periodic)
         use types
         type(field), intent(inout) :: f
         real*8, intent(in) :: v(3)
         real*8 :: grd0
         logical, intent(in), optional :: periodic
       end function grd0
    end interface

    real*8 :: err, fpp, fmp, fpm, fmm, f
    real*8 :: hh1, hh2, erract, ww
    real*8 :: n(ndif_jmax,ndif_jmax)
    integer :: i, j

    der2ij = 0d0
    hh1 = h1
    hh2 = h2
    f = grd0(fld,x+dir1*hh1+dir2*hh2,periodic)
    fpp = f
    f = grd0(fld,x+dir1*hh1-dir2*hh2,periodic)
    fpm = f
    f = grd0(fld,x-dir1*hh1+dir2*hh2,periodic)
    fmp = f
    f = grd0(fld,x-dir1*hh1-dir2*hh2,periodic)
    fmm = f
    n(1,1) = (fpp - fmp - fpm + fmm ) / (4d0*hh1*hh2)
    err = big
    do j = 2, ndif_jmax
       hh1 = hh1 / derw
       hh2 = hh2 / derw
       f = grd0(fld,x+dir1*hh1+dir2*hh2,periodic)
       fpp = f
       f = grd0(fld,x+dir1*hh1-dir2*hh2,periodic)
       fpm = f
       f = grd0(fld,x-dir1*hh1+dir2*hh2,periodic)
       fmp = f
       f = grd0(fld,x-dir1*hh1-dir2*hh2,periodic)
       fmm = f
       n(1,j) = (fpp - fmp - fpm + fmm) / (4d0*hh1*hh2)
       ww = derw2
       do i = 2, j
          n(i,j) = (ww*n(i-1,j)-n(i-1,j-1))/(ww-1d0)
          ww = ww * derw2
          erract = max (abs(n(i,j)-n(i-1,j)), abs(n(i,j)-n(i-1,j-1)))
          if (erract.le.err) then
             err = erract
             der2ij = n(i,j)
          endif
       enddo
       if ( abs(n(j,j)-n(j-1,j-1)) .gt. safe*err .or. err .le. errcnv ) return
    enddo
  end function der2ij
  
end module fields
