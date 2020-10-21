module fca_xtofca_adj_mod

  use fp_types_m, only: fp
  use core_disp_types_m, only: fca_gridded_disp, &
       ims,ime,jms,jme,kms,kme,its,ite,jts,jte,kts,kte
  use core_disp_func_m, only: allocate_disp, deallocate_disp, init_meta
  use fca_wrf_grid_types_m, only: fca_wrf_grid
  use fca_wrf_grid_func_m, only: fca_allocate_wrf_grid, fca_deallocate_wrf_grid, fca_zero_wrf_grid
  use xtofca_wrf_adj_m, only: xtofca_wrf_adj

  use fca_gsi_inter_m, only: ges_to_fca_wrf, sval_to_disp_grid_adj, fca_state_to_sval_adj, &
       uv_zlevel_par, fca_interp_order, th_compute_par, p_qv, nmoist

  use gsi_bundlemod, only : gsi_bundle

  implicit none

  private

  public :: xtofca_adj

contains
subroutine xtofca_adj(sval, flag_linear)
  ! Adjoint of:
  ! -----------------------------------------------------------------
  ! convert GSI bg, displacement vectors to gridded analysis increments (also in grid)
  ! This is a GSI-specific wrapper for the generic xtofca_wrf, WRF-specific routine
  ! -----------------------------------------------------------------

    implicit none

    type(gsi_bundle), intent(inout) :: sval(:)
    logical, intent(in) :: flag_linear
    real(fp), parameter :: dx=1,dy=1,x0=0,y0=0			! grid spacing paramters, set manually for now
    type (fca_wrf_grid) :: bg_state, inc_state
    type (fca_gridded_disp) :: disp, disp_ad
    integer :: istep = 10000  ! only used for step-wise testing of fca_disp_tl/ad
    integer :: Nx, Ny, uv_zlevel
    integer :: status

    integer :: i
    real (fp) :: work2d(ims:ime,jms:jme,3)

    ! find the domain size
    Nx = ite - its + 1 ; Ny = jte - jts + 1
    uv_zlevel = min(kte,max(kts,int(kts+(kte-kts)*uv_zlevel_par+0.5)))

    !  copy the bg from GSI to our FCA type
    !  for DM_PARALLEL, any needed halo exchanges are done inside ges_to_fca_wrf
    call fca_allocate_wrf_grid(bg_state,nmoist,status)
    if (status .ne. 0) write(*,*) '*** xtofca: failed to allocate bg_state ***, status=',status
    call ges_to_fca_wrf(bg_state,status)
    if (status .ne. 0) write(*,*) '*** xtofca: ges_to_fca_wrf failed ***, status=',status

    !initialize all of the displaced fields
    disp%meta = init_meta(ite-its+1, jte-jts+1, dx, dy, x0, y0)
    ! initialize disp_tl with same dimensions and metadata
    call allocate_disp(disp,.TRUE.,status)
    if (status .ne. 0) write(*,*) '*** xtofca_adj: failed to allocate disp ***, status=',status

    ! initialize the displacement as the lowest-level u,v components as a first guess
    if (.not. flag_linear) then
       ! Error: should only ever be called with flag_linear=.TRUE.
        write (*,*) 'Internal logic error: xtofca_adj can only be called with flag_linear=.TRUE.'
    else
       ! initialize disp_ad with same dimensions and metadata
       disp_ad%meta = disp%meta
       ! allocate disp_ad (will be zeroed in xtofca_wrf_ad):
       call allocate_disp(disp_ad,.FALSE.,status)
       if (status .ne. 0) write(*,*) '*** xtofca_adj: failed to allocate disp_ad ***, status=',status
!        write(*,*) '*** xtofca_adj debug: allocate disp_ad status=', status

       ! Zero local adjoint:
       call fca_allocate_wrf_grid(inc_state,nmoist,status)
       if (status .ne. 0) write(*,*) '*** xtofca_adj: failed to allocate inc_state ***, status=',status
!        write(*,*) '*** xtofca_adj debug: allocate inc_stat status=', status
       call fca_zero_wrf_grid(inc_state)

       call fca_state_to_sval_adj(bg_state, inc_state, flag_linear, sval, status)
       if (status .ne. 0) write(*,*) '*** xtofca_adj: fca_state_to_sval_adj failed ***, status=',status
!        write(*,*) '*** xtofca_adj debug: fca_state_to_sval_adj status=', status
       call xtofca_wrf_adj(bg_state,disp,disp_ad,inc_state,flag_linear,p_qv,fca_interp_order,th_compute_par)
!        write(*,*) '*** xtofca_adj debug: returned from xtofca_wrf_adj'
       
       ! zero sval (in WRFDA: da_zero_x(grid%xa)), done inside sval_to_disp_grid_adj
       ! for DM_PARALLEL, any needed halo exchanges are done inside sval_to_disp_grid_adj
       call sval_to_disp_grid_adj(sval,disp_ad,uv_zlevel,status)
       if (status .ne. 0) write(*,*) '*** xtofca_adj: sval_to_disp_grid_adj failed ***, status=',status
!        write(*,*) '*** xtofca_adj debug: sval_to_disp_grid_adj status=', status

    end if

    ! deallocate: disp, disp_ad, bg_state, inc_state
    call deallocate_disp(disp,status)
    if (status .ne. 0) write(*,*) '*** xtofca_adj: failed to deallocate disp ***, status=',status
!     write(*,*) '*** xtofca_adj debug: deallocate disp status=', status
    if (flag_linear) then
       call deallocate_disp(disp_ad,status)
       if (status .ne. 0) write(*,*) '*** xtofca_adj: failed to deallocate disp_ad ***, status=',status
!        write(*,*) '*** xtofca_adj debug: deallocate disp_ad status=', status
    end if
    call fca_deallocate_wrf_grid(bg_state,status)
    if (status .ne. 0) write(*,*) '*** xtofca_adj: failed to deallocate bg_state ***, status=',status
!     write(*,*) '*** xtofca_adj debug: deallocate bg_state status=', status
    call fca_deallocate_wrf_grid(inc_state,status)
    if (status .ne. 0) write(*,*) '*** xtofca_adj: failed to deallocate inc_state ***, status=',status
!     write(*,*) '*** xtofca_adj debug: deallocate inc_state status=', status
    
end subroutine xtofca_adj
end module fca_xtofca_adj_mod